# Makefile for constructing RPMs.
# Try "make" (for SRPMS) or "make rpm"

NAME = ceph-ansible

# Set the RPM package NVR from "git describe".
# Examples:
#
#  A "git describe" value of "v2.2.0beta1" would create an NVR
#  "ceph-ansible-2.2.0-0.beta1.1.el8"
#
#  A "git describe" value of "v2.2.0rc1" would create an NVR
#  "ceph-ansible-2.2.0-0.rc1.1.el8"
#
#  A "git describe" value of "v2.2.0rc1-1-gc465f85" would create an NVR
#  "ceph-ansible-2.2.0-0.rc1.1.gc465f85.el8"
#
#  A "git describe" value of "v2.2.0" creates an NVR
#  "ceph-ansible-2.2.0-1.el8"

TAG := $(shell git describe --tags --abbrev=0 --match 'v*')
VERSION := $(shell echo $(TAG) | sed 's/^v//')
COMMIT := $(shell git rev-parse HEAD)
SHORTCOMMIT := $(shell echo $(COMMIT) | cut -c1-7)
RELEASE := $(shell git describe --tags --match 'v*' \
             | sed 's/^v//' \
             | sed 's/^[^-]*-//' \
             | sed 's/-/./')
ifeq ($(VERSION),$(RELEASE))
  RELEASE = 1
endif
ifneq (,$(findstring beta,$(VERSION)))
    BETA := $(shell echo $(VERSION) | sed 's/.*beta/beta/')
    RELEASE := 0.$(BETA).$(RELEASE)
    VERSION := $(subst $(BETA),,$(VERSION))
endif
ifneq (,$(findstring rc,$(VERSION)))
    RC := $(shell echo $(VERSION) | sed 's/.*rc/rc/')
    RELEASE := 0.$(RC).$(RELEASE)
    VERSION := $(subst $(RC),,$(VERSION))
endif

ifneq (,$(shell echo $(VERSION) | grep [a-zA-Z]))
    # If we still have alpha characters in our Git tag string, we don't know
    # how to translate that into a sane RPM version/release. Bail out.
    $(error cannot translate Git tag version $(VERSION) to an RPM NVR)
endif

NVR := $(NAME)-$(VERSION)-$(RELEASE).el8

all: srpm

# Testing only
echo:
	echo COMMIT $(COMMIT)
	echo VERSION $(VERSION)
	echo RELEASE $(RELEASE)
	echo NVR $(NVR)

clean:
	rm -rf dist/
	rm -rf ceph-ansible-$(VERSION)-$(SHORTCOMMIT).tar.gz
	rm -rf $(NVR).src.rpm

dist:
	git archive --format=tar.gz --prefix=ceph-ansible-$(VERSION)/ HEAD > ceph-ansible-$(VERSION)-$(SHORTCOMMIT).tar.gz

spec:
	sed ceph-ansible.spec.in \
	  -e 's/@COMMIT@/$(COMMIT)/' \
	  -e 's/@VERSION@/$(VERSION)/' \
	  -e 's/@RELEASE@/$(RELEASE)/' \
	  > ceph-ansible.spec

srpm: dist spec
	rpmbuild -bs ceph-ansible.spec \
	  --define "_topdir ." \
	  --define "_sourcedir ." \
	  --define "_srcrpmdir ." \
	  --define "dist .el8"

rpm: dist srpm
	mock -r epel-7-x86_64 rebuild $(NVR).src.rpm \
	  --resultdir=. \
	  --define "dist .el8"

tag:
	$(eval BRANCH := $(shell git rev-parse --abbrev-ref HEAD))
	$(eval LASTNUM := $(shell echo $(TAG) \
	                    | sed -E "s/.*[^0-9]([0-9]+)$$/\1/"))
	$(eval NEXTNUM=$(shell echo $$(($(LASTNUM)+1))))
	$(eval NEXTTAG=$(shell echo $(TAG) | sed "s/$(LASTNUM)$$/$(NEXTNUM)/"))
	if [[ "$(TAG)" == "$(git describe --tags --match 'v*')" ]]; then \
	    echo "$(SHORTCOMMIT) on $(BRANCH) is already tagged as $(TAG)"; \
	    exit 1; \
	fi
	if [[ "$(BRANCH)" != "master" ]] && \
	   ! [[ "$(BRANCH)" =~ ^stable- ]]; then \
		echo Cannot tag $(BRANCH); \
		exit 1; \
	fi
	@echo Tagging Git branch $(BRANCH)
	git tag $(NEXTTAG)
	@echo run \'git push origin $(NEXTTAG)\' to push to GitHub.

.PHONY: dist rpm srpm tag

##################################################
# additional helpers
build:
	ansible-playbook -i ./inventory site.yml

purge:
	ansible-playbook -i ./inventory infrastructure-playbooks/my-purge-cluster.yml

update:
	ansible-playbook -i ./inventory infrastructure-playbooks/rolling_update.yml


RBD_POOL=volumes
RBD_IMAGE=foo
RBD_MOUNT=/mnt/ceph-block-device

testrbd:
	# setup and test
	# https://docs.ceph.com/docs/master/start/quick-rbd/
	# https://rhcs-test-drive.readthedocs.io/en/latest/Module-1/
	sudo rbd --cluster ceph pool init $(RBD_POOL)
	sudo rbd --cluster ceph --name client.admin --pool $(RBD_POOL) create $(RBD_IMAGE) --size 4096 --image-feature layering
	sudo rbd --cluster ceph --name client.admin --pool $(RBD_POOL) map $(RBD_IMAGE)
	sudo mkfs.ext4 -m0 /dev/rbd/$(RBD_POOL)/$(RBD_IMAGE)
	sudo mkdir $(RBD_MOUNT)
	sudo mount /dev/rbd/$(RBD_POOL)/$(RBD_IMAGE) $(RBD_MOUNT)
	ls -latr $(RBD_MOUNT)
	df $(RBD_MOUNT)
	date | sudo tee -a $(RBD_MOUNT)/test.txt
	ls -latr $(RBD_MOUNT)
	sudo umount $(RBD_MOUNT)
	ls -latr $(RBD_MOUNT)
	sudo mount /dev/rbd/$(RBD_POOL)/$(RBD_IMAGE) $(RBD_MOUNT)
	ls -latr $(RBD_MOUNT)
	sudo cat $(RBD_MOUNT)/test.txt
	# destroy
	sudo umount $(RBD_MOUNT)
	sudo rbd --cluster ceph --name client.admin --pool $(RBD_POOL) unmap $(RBD_IMAGE)
	sudo rbd --cluster ceph --name client.admin --pool $(RBD_POOL) remove $(RBD_IMAGE)
	sudo rm -rf $(RBD_MOUNT)

CEPHFS_FS=cephfs
CEPHFS_MOUNT=/mnt/ceph-fs

testcephfs:
	# setup and test
	# https://docs.ceph.com/docs/master/start/quick-cephfs/
	# https://docs.ceph.com/docs/master/cephfs/createfs/
	#
	# sudo ceph --cluster ceph osd pool create $(CEPHFS_FS)_data 32
	# sudo ceph --cluster ceph osd pool create $(CEPHFS_FS)_metadata 32
	# sudo ceph --cluster ceph fs new $(CEPHFS_FS) $(CEPHFS_FS)_metadata $(CEPHFS_FS)_data
	sudo ceph --cluster ceph fs ls
	sudo ceph --cluster ceph mds stat
	sudo mkdir -p $(CEPHFS_MOUNT)
	sudo mount -t ceph :/ $(CEPHFS_MOUNT) -o mds_namespace=$(CEPHFS_FS) -o name=admin
	sudo ls -latr $(CEPHFS_MOUNT)
	date | sudo tee -a $(CEPHFS_MOUNT)/test.txt
	sudo umount $(CEPHFS_MOUNT)
	sudo mount -t ceph :/ $(CEPHFS_MOUNT) -o mds_namespace=$(CEPHFS_FS) -o name=admin
	sudo ls -latr $(CEPHFS_MOUNT)
	sudo cat $(CEPHFS_MOUNT)/test.txt
	sudo umount $(CEPHFS_MOUNT)
	sudo rmdir $(CEPHFS_MOUNT)
	# sudo ceph --cluster ceph fs rm $(CEPHFS_FS) --yes-i-really-mean-it
	# sudo ceph --cluster ceph osd pool delete $(CEPHFS_FS)_data $(CEPHFS_FS)_data --yes-i-really-really-mean-it
	# sudo ceph --cluster ceph osd pool delete $(CEPHFS_FS)_metadata $(CEPHFS_FS)_metadata --yes-i-really-really-mean-it


RGW_USER=test
RGW_CONT=container1

testrgw:
	# setup test accounts
	# https://rhcs-test-drive.readthedocs.io/en/latest/Module-3/
	sudo radosgw-admin user create --uid="$(RGW_USER)" --display-name="$(RGW_USER) API User" --access-key="$(RGW_USER)" --secret-key="$(RGW_USER)key"
	sudo radosgw-admin subuser create --uid="$(RGW_USER)" --subuser="$(RGW_USER):swift" --secret-key="$(RGW_USER)key" --access=full
	DEVICE=`ip link | grep 'state UP' | awk '{print $$2}' | sed 's/://'` && \
	IP=`ifconfig $${DEVICE} | grep inet | head -1 | awk '{print $$2}'` && \
	swift -A http://$${IP}:8180/auth/  -U "$(RGW_USER):swift"  -K "$(RGW_USER)key" list && \
	swift -A http://$${IP}:8180/auth/  -U "$(RGW_USER):swift"  -K "$(RGW_USER)key" post $(RGW_CONT) && \
	swift -A http://$${IP}:8180/auth/  -U "$(RGW_USER):swift"  -K "$(RGW_USER)key" list && \
	swift -A http://$${IP}:8180/auth/  -U "$(RGW_USER):swift"  -K "$(RGW_USER)key" upload $(RGW_CONT) /etc/hosts && \
	swift -A http://$${IP}:8180/auth/  -U "$(RGW_USER):swift"  -K "$(RGW_USER)key" list && \
	swift -A http://$${IP}:8180/auth/  -U "$(RGW_USER):swift"  -K "$(RGW_USER)key" download $(RGW_CONT) etc/hosts -o - && \
	s3cmd --access_key=$(RGW_USER) --secret_key=$(RGW_USER)key --host=$${IP}:8180  --no-ssl ls && \
	s3cmd --access_key=$(RGW_USER) --secret_key=$(RGW_USER)key --host=$${IP}:8180  --no-ssl mb s3://$(RGW_CONT)s3made && \
	s3cmd --access_key=$(RGW_USER) --secret_key=$(RGW_USER)key --host=$${IP}:8180  --no-ssl info s3://$(RGW_CONT)/etc/hosts && \
	s3cmd --access_key=$(RGW_USER) --secret_key=$(RGW_USER)key --host=$${IP}:8180  --no-ssl ls s3://$(RGW_CONT)/etc/ && \
	s3cmd --access_key=$(RGW_USER) --secret_key=$(RGW_USER)key --host=$${IP}:8180  --no-ssl get s3://$(RGW_CONT)/etc/hosts -



# sorting out pg_nums
# https://stackoverflow.com/questions/39589696/ceph-too-many-pgs-per-osd-all-you-need-to-know
# benchmarking
# http://tracker.ceph.com/projects/ceph/wiki/Benchmark_Ceph_Cluster_Performance

# delete pools
# https://stackoverflow.com/questions/45012905/removing-pool-mon-allow-pool-delete-config-option-to-true-before-you-can-destro

# ceph osd pool stats
# ceph osd pool set scbench size 1
