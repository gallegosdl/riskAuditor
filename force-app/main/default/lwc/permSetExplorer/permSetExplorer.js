import { LightningElement, wire, track } from 'lwc';
import getPermissionBooleans from '@salesforce/apex/PermissionSetDescribeService.getPermissionBooleans';
import getProfilesWithPermission from '@salesforce/apex/PermissionSetDescribeService.getProfilesWithPermission';
import getErrorMessage from '@salesforce/apex/PermissionSetDescribeService.getErrorMessage';

export default class PermSetExplorer extends LightningElement {
    permOptions = [];
    @track selectedPerm = '';
    @track pageSize = 25;
    @track pageNum = 1;
    @track total = 0;
    @track rows = [];
    @track errorMessage = '';
    loading = false;

    columns = [
        { label: 'Permission', fieldName: 'permissionLabel', type: 'text', cellAttributes: { class: { fieldName: 'permissionPillClass' } } },
        { label: 'Permission Set', fieldName: 'psUrl', type: 'url', typeAttributes: { label: { fieldName: 'permissionSetLabel' }, target: '_blank' } },
        { label: 'Profile', fieldName: 'profileUrl', type: 'url', typeAttributes: { label: { fieldName: 'profileName' }, target: '_blank' } },
    ];

    pageSizeOptions = [
        { label: '25', value: 25 },
        { label: '50', value: 50 },
        { label: '100', value: 100 },
    ];

    @wire(getPermissionBooleans)
    wiredPerms({ data, error }) {
        if (data) {
            this.permOptions = data.map(p => ({
                label: `${p.label} (${p.apiName})`,
                value: p.apiName
            }));
            this.errorMessage = '';
        } else if (error) {
            console.error('Error fetching permissions', error);
            this.errorMessage = error.body?.message || 'Failed to fetch permission options';
            this.permOptions = [];
        }
    }

    get totalPages() {
        return this.pageSize > 0 ? Math.max(1, Math.ceil(this.total / this.pageSize)) : 1;
    }
    get isFirst() { return this.pageNum <= 1; }
    get isLast() { return this.pageNum >= this.totalPages; }
    get hasError() { return this.errorMessage !== ''; }
    get hasPermOptions() { return this.permOptions.length > 0; }
    get hasNoPermOptions() { return !this.loading && this.permOptions.length === 0 && !this.hasError; }

    handlePermChange = (e) => { this.selectedPerm = e.detail.value; this.pageNum = 1; this.fetch(); };
    handlePageSizeChange = (e) => { this.pageSize = parseInt(e.detail.value, 10) || 50; this.pageNum = 1; this.fetch(); };
    refresh = () => { this.fetch(); };
    goFirst = () => { if (!this.isFirst) { this.pageNum = 1; this.fetch(); } };
    goPrev = () => { if (!this.isFirst) { this.pageNum -= 1; this.fetch(); } };
    goNext = () => { if (!this.isLast) { this.pageNum += 1; this.fetch(); } };
    goLast = () => { if (!this.isLast) { this.pageNum = this.totalPages; this.fetch(); } };

    handlePermissionChange(event) {
        const selectedPermission = event.detail.value;
        if (selectedPermission) {
            this.selectedPermission = selectedPermission;
            this.loading = true;
            
            getProfilesWithPermission({ 
                permissionApi: selectedPermission, 
                pageNum: 1, 
                pageSize: this.pageSize 
            })
            .then(result => {
                this.profileData = result;
                this.error = undefined;
                this.loading = false; // Ensure this line is here to stop spinner
            })
            .catch(error => {
                this.error = error;
                this.profileData = undefined;
                this.loading = false; // Ensure this line is here to stop spinner
                console.error('Error fetching profiles with permission', error);
            });
        } else {
            this.profileData = undefined;
            this.error = undefined;
        }
    }

    async fetch() {
        if (!this.selectedPerm) { this.rows = []; this.total = 0; return; }
        this.loading = true;
        this.errorMessage = '';

        try {
            const res = await getProfilesWithPermission({
                permissionApi: this.selectedPerm,
                pageNum: this.pageNum,
                pageSize: this.pageSize
            });

            this.total = res?.total || 0;
            this.rows = (res?.items || []).map((r, i) => ({
                key: `${this.pageNum}-${i}-${r.permissionSetId}`,
                ...r,
                permissionPillClass: 'pill pill--perm',
                psUrl: '/' + r.permissionSetId,
                profileUrl: r.profileId ? ('/' + r.profileId) : null
            }));
            
            this.loading = false;
        } catch (error) {
            this.rows = [];
            this.total = 0;

            try {
                // Use the template-based error messaging
                const errorCode = error.body?.errorCode || 'ERROR';
                this.errorMessage = await getErrorMessage({
                    errorCode: errorCode,
                    permissionApi: this.selectedPerm,
                    recordCount: 0
                });
            } catch (templateError) {
                // Fallback to basic error handling
                this.errorMessage = error.body?.message || 'An error occurred while fetching data';
            }

            console.error('Error in fetch:', error);
        }
    }
}
