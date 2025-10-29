WITH RankedQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.AnswerCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
      AND p.Title IS NOT NULL
      AND p.AnswerCount IS NOT NULL
),
UserActivity AS (
    SELECT
        ph.UserId AS UserId,
        COUNT(DISTINCT ph.PostId) AS TotalPosts,
        SUM(CASE WHEN pht.Name IN ('Edit Body', 'Edit Title', 'Edit Tags') THEN 1 ELSE 0 END) AS TotalEdits,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS TotalUpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS TotalDownVotes
    FROM PostHistory ph
    LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Votes v ON ph.PostId = v.PostId AND ph.UserId = v.UserId
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
FrequentTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS TagCount
    FROM Tags t
    JOIN Posts p ON POSITION(t.TagName IN p.Tags) > 0 AND p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 1000
),
TopRatedUsers AS (
    SELECT
        OwnerUserId AS UserId,
        SUM(Score) AS TotalScore
    FROM Posts
    WHERE PostTypeId = 2
      AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
    ORDER BY SUM(Score) DESC
    LIMIT 100
)
SELECT
    rq.PostId,
    rq.Title AS QuestionTitle,
    rq.OwnerDisplayName AS QuestionOwner,
    rq.PostCreationDate,
    rq.Score AS QuestionScore,
    rq.AnswerCount,
    rq.FavoriteCount,
    ua.TotalPosts AS UserTotalPosts,
    ua.TotalEdits AS UserTotalEdits,
    ua.TotalUpVotes AS UserTotalUpVotes,
    ua.TotalDownVotes AS UserTotalDownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId) AS CommentCountOnQuestion,
    COALESCE(t.TagCount, 0) AS FrequentTagCount,
    CASE
        WHEN rq.Score > 100 THEN 'High Score'
        WHEN rq.AnswerCount > 10 THEN 'Popular'
        ELSE 'Standard'
    END AS QuestionCategory,
    CASE
        WHEN tr.UserId IS NOT NULL THEN 'Top Rated User'
        ELSE 'Regular User'
    END AS UserRatingStatus,
    ('https://example.com/questions/' || CAST(rq.PostId AS VARCHAR(50))) AS QuestionLink,
    UPPER(SUBSTRING(rq.Title FROM 1 FOR 3)) AS TitlePrefix,
    CASE WHEN rq.OwnerUserId IN (SELECT UserId FROM TopRatedUsers) THEN 1 ELSE 0 END AS IsTopRatedUserFlag
FROM RankedQuestions rq
LEFT JOIN UserActivity ua ON rq.OwnerUserId = ua.UserId
LEFT JOIN (
    SELECT DISTINCT TagName FROM FrequentTags
) ft ON POSITION(ft.TagName IN rq.Title) > 0
LEFT JOIN (
    SELECT f.TagName, f.TagCount
    FROM FrequentTags f
) t ON t.TagName = ft.TagName
LEFT JOIN TopRatedUsers tr ON rq.OwnerUserId = tr.UserId
WHERE rq.RowNum <= 10
  AND EXISTS (
    SELECT 1
    FROM Posts a
    WHERE a.ParentId = rq.PostId
      AND a.PostTypeId = 2
      AND a.Score > 5
  )
ORDER BY rq.PostCreationDate DESC
LIMIT 50;