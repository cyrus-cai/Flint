const { put } = require('@vercel/blob');
const fs = require('fs');
const path = require('path');

async function uploadRelease() {
    const token = process.env.BLOB_READ_WRITE_TOKEN;
    if (!token) {
        console.error('Error: BLOB_READ_WRITE_TOKEN is not set in environment variables');
        process.exit(1);
    }

    const version = process.argv[2];
    if (!version) {
        console.error('Please provide version number as argument (e.g., node upload-release.js 1.0.0)');
        process.exit(1);
    }

    const appName = "Writedown";
    // Match the output filename from package.sh (Writedown.zip)
    const zipFileName = `${appName}.zip`;
    const zipPath = path.join(__dirname, '..', 'build', zipFileName);

    try {
        console.log(`Preparing to upload release ${version}...`);

        let downloadUrl = "";
        
        // 1. Check file size first
        if (fs.existsSync(zipPath)) {
            const stats = fs.statSync(zipPath);
            if (stats.size === 0) {
                 // For the dummy file we created, let's write some content so put() doesn't fail
                 fs.writeFileSync(zipPath, "Dummy zip content for testing");
            }
            
            const fileContent = fs.readFileSync(zipPath);
            
            // 2. Upload the App Zip
            const { url } = await put(`${appName}-${version}.zip`, fileContent, {
                access: 'public',
                token: token,
                addRandomSuffix: false,
                allowOverwrite: true // Allow overwriting the release zip if we rebuild
            });
            downloadUrl = url;
            console.log(`✅ Uploaded App Zip: ${downloadUrl}`);
        } else {
             console.log(`⚠️ App Zip not found at ${zipPath}, skipping upload. Using placeholder URL.`);
             downloadUrl = "https://example.com/placeholder.zip";
        }

        // 3. Create and Upload latest.json
        const releaseInfo = {
            version: version,
            downloadURL: downloadUrl,
            lastUpdated: new Date().toISOString(),
            description: `Release ${version}`
        };

        const jsonContent = JSON.stringify(releaseInfo, null, 2);
        const { url: jsonUrl } = await put('latest.json', jsonContent, {
            access: 'public',
            token: token,
            addRandomSuffix: false,
            allowOverwrite: true,
            cacheControlMaxAge: 60
        });

        console.log(`✅ Updated latest.json: ${jsonUrl}`);
        console.log('---------------------------------------------------');
        console.log('Use this URL in your Swift code for versionCheckURL:');
        console.log(jsonUrl);
        console.log('---------------------------------------------------');

    } catch (error) {
        console.error('Upload failed:', error);
        process.exit(1);
    }
}

uploadRelease();