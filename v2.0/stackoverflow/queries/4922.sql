WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn,
        p.PostTypeId,
        p.AnswerCount,
        p.FavoriteCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.Title IS NOT NULL AND pt.Name IN ('Question', 'Answer')
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        MAX(p.LastActivityDate) AS LastUserActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
HighReputationUsers AS (
    SELECT
        UserId
    FROM UserPostActivity
    WHERE Reputation > 10000
),
PostsWithEdits AS (
    SELECT
        p.Id AS PostId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY p.Id
),
PopularTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS TagPostCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    GROUP BY t.TagName
    ORDER BY TagPostCount DESC
    LIMIT 10
),
RecentClosedQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title AS QuestionTitle,
        p.ClosedDate,
        crt.Name AS CloseReason
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
    ORDER BY p.ClosedDate DESC
    LIMIT 5
),
AllPostDetails AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.PostTypeName,
        rp.PostCreationDate,
        upa.DisplayName AS OwnerDisplayName,
        upa.Reputation AS OwnerReputation,
        pe.EditCount,
        pe.LastEditDate,
        CASE WHEN rp.PostTypeName = 'Question' AND rp.AnswerCount > 0 THEN rp.AnswerCount ELSE 0 END AS AnswerCount,
        CASE WHEN rp.PostTypeName = 'Question' AND rp.FavoriteCount IS NOT NULL THEN rp.FavoriteCount ELSE 0 END AS FavoriteCount,
        CASE WHEN rp.PostTypeName = 'Question' AND rp.AnswerCount IS NULL THEN 1 ELSE 0 END AS IsAnswerCountNull,
        CASE WHEN u.UserId IS NOT NULL THEN 'HighReputationOwner' ELSE 'StandardOwner' END AS OwnerCategory,
        rp.rn
    FROM RankedPosts rp
    JOIN UserPostActivity upa ON rp.OwnerUserId = upa.UserId
    LEFT JOIN PostsWithEdits pe ON rp.PostId = pe.PostId
    LEFT JOIN HighReputationUsers u ON rp.OwnerUserId = u.UserId
    WHERE rp.rn <= 100
    GROUP BY
        rp.PostId,
        rp.Title,
        rp.PostTypeName,
        rp.PostCreationDate,
        upa.DisplayName,
        upa.Reputation,
        pe.EditCount,
        pe.LastEditDate,
        rp.AnswerCount,
        rp.FavoriteCount,
        u.UserId,
        rp.rn
)
SELECT
    apd.PostId,
    apd.Title,
    apd.PostTypeName,
    apd.PostCreationDate,
    apd.OwnerDisplayName,
    apd.OwnerReputation,
    apd.EditCount,
    apd.LastEditDate,
    apd.AnswerCount,
    apd.FavoriteCount,
    apd.IsAnswerCountNull,
    apd.OwnerCategory,
    rcq.QuestionTitle AS RecentClosedTitle,
    rcq.CloseReason AS RecentCloseReason,
    CASE
        WHEN apd.OwnerReputation > 50000 AND COALESCE(apd.EditCount, 0) > 10 THEN 'VeteranHighReputationEditor'
        WHEN apd.OwnerReputation > 10000 AND COALESCE(apd.AnswerCount, 0) > 5 THEN 'ExperiencedAnswerer'
        WHEN COALESCE(apd.EditCount, 0) > 5 AND apd.PostTypeName = 'Question' THEN 'ActiveEditor'
        ELSE 'GeneralUser'
    END AS UserActivityLevel
FROM AllPostDetails apd
LEFT JOIN RecentClosedQuestions rcq ON apd.PostId = rcq.PostId

UNION ALL

SELECT
    NULL AS PostId,
    NULL AS Title,
    'TagSummary' AS PostTypeName,
    NULL AS PostCreationDate,
    pt.TagName AS OwnerDisplayName,
    pt.TagPostCount AS OwnerReputation,
    NULL AS EditCount,
    NULL AS LastEditDate,
    NULL AS AnswerCount,
    NULL AS FavoriteCount,
    NULL AS IsAnswerCountNull,
    NULL AS OwnerCategory,
    NULL AS RecentClosedTitle,
    NULL AS RecentCloseReason,
    NULL AS UserActivityLevel
FROM PopularTags pt
WHERE pt.TagPostCount > 10000

ORDER BY OwnerReputation DESC NULLS LAST, PostCreationDate DESC NULLS LAST
LIMIT 1000;