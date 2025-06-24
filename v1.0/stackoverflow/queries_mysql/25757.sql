
WITH TagFrequencies AS (
    SELECT
        SUBSTRING_INDEX(SUBSTRING_INDEX(Tags, '><', numbers.n), '><', -1) AS TagName,
        COUNT(*) AS TagCount
    FROM Posts
    JOIN (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
          UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) numbers
    ON CHAR_LENGTH(Tags) - CHAR_LENGTH(REPLACE(Tags, '><', '')) >= numbers.n - 1
    WHERE PostTypeId = 1  
    GROUP BY TagName
),
TopTags AS (
    SELECT
        TagName,
        TagCount,
        @rownum := @rownum + 1 AS Rank
    FROM TagFrequencies, (SELECT @rownum := 0) r
    ORDER BY TagCount DESC
),
PopularUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.Score) AS TotalScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2) 
    GROUP BY u.Id, u.DisplayName
),
TopUsers AS (
    SELECT
        UserId,
        DisplayName,
        TotalViews,
        TotalScore,
        @rownum2 := @rownum2 + 1 AS Rank
    FROM PopularUsers, (SELECT @rownum2 := 0) r
    ORDER BY TotalViews DESC
),
RecentActivity AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        ph.CreationDate AS EditDate,
        ph.UserDisplayName AS Editor,
        ph.Comment AS EditComment
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) 
    ORDER BY ph.CreationDate DESC
)
SELECT
    t.TagName,
    t.TagCount,
    u.DisplayName AS PopularUser,
    u.TotalViews,
    u.TotalScore,
    r.PostId,
    r.Title AS RecentPostTitle,
    r.CreationDate AS PostCreationDate,
    r.EditDate AS LastEditDate,
    r.Editor AS LastEditor,
    r.EditComment
FROM TopTags t
JOIN TopUsers u ON u.Rank <= 10  
JOIN RecentActivity r ON r.EditDate >= NOW() - INTERVAL 30 DAY
WHERE t.Rank <= 10  
ORDER BY t.TagCount DESC, u.TotalViews DESC, r.EditDate DESC;
