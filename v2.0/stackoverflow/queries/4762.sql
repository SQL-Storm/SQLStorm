-- {"query": "4762.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 758}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
RecentQuestions AS (
    SELECT
        PostId,
        OwnerUserId,
        Title,
        OwnerDisplayName,
        CreationDate,
        Score,
        AnswerCount
    FROM RankedPosts
    WHERE rn <= 5
),
UserTopTags AS (
    SELECT
        t.TagName,
        SUBSTRING(p.Tags FROM 2 FOR POSITION('>' IN p.Tags) - 2) AS FirstTag,
        COUNT(p.Id) AS TagCount,
        SUM(p.Score) AS TotalScore,
        u.Id AS UserId,
        u.DisplayName AS UserName,
        p.Tags
    FROM Posts p
    JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY t.TagName, p.Tags, u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 10
),
TopUsersWithTopTags AS (
    SELECT
        utt.TagName,
        utt.FirstTag,
        utt.UserName,
        utt.UserId,
        utt.TagCount,
        utt.TotalScore,
        ROW_NUMBER() OVER (PARTITION BY utt.UserId ORDER BY utt.TagCount DESC, utt.TotalScore DESC) AS user_rn
    FROM UserTopTags utt
)
SELECT
    COALESCE(rq.Title, 'N/A') AS QuestionTitle,
    rq.OwnerDisplayName,
    rq.CreationDate,
    rq.Score,
    rq.AnswerCount,
    COALESCE(tuwtt.TagName, 'General') AS PrimaryTag,
    tuwtt.TagCount,
    tuwtt.TotalScore,
    CASE
        WHEN rq.Score > 100 THEN 'High Score'
        WHEN rq.AnswerCount > 5 THEN 'Popular Answered'
        ELSE 'Standard'
    END AS QuestionCategory,
    CASE
        WHEN EXTRACT(ISODOW FROM rq.CreationDate) IN (6, 7) THEN 'Weekend'
        ELSE 'Weekday'
    END AS DayOfWeek,
    COALESCE(NULLIF(u.Location, ''), 'Unknown Location') AS UserLocation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId AND c.UserId = rq.OwnerUserId) AS UserCommentsOnQuestion,
    rq.PostId,
    rq.OwnerUserId
FROM RecentQuestions rq
LEFT JOIN Users u ON rq.OwnerUserId = u.Id
LEFT JOIN TopUsersWithTopTags tuwtt ON rq.OwnerUserId = tuwtt.UserId AND tuwtt.user_rn = 1
WHERE rq.Score > 0 OR rq.AnswerCount > 0
ORDER BY rq.CreationDate DESC
FETCH FIRST 100 ROWS ONLY;