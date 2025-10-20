-- {"query": "3085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 874} 
WITH PopularTags AS (
    SELECT
        TagName,
        COUNT(*) AS TagCount,
        MAX(Count) OVER () AS MaxTagCount
    FROM Tags
    WHERE IsModeratorOnly = FALSE
    GROUP BY TagName
),
RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RN
    FROM Posts p
    WHERE p.PostTypeId = 1
),
HighestReputationUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputRank
    FROM Users u
),
QuestionAnswers AS (
    SELECT
        q.QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore
    FROM Posts q
    LEFT OUTER JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    GROUP BY q.QuestionId
),
PostComments AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.Score) AS MaxCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
LatestPostHistory AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS LastHistoryDate,
        ph.PostHistoryTypeId
    FROM (
        SELECT
            ph.*,
            ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS RN
        FROM PostHistory ph
    ) ph
    WHERE ph.RN = 1
),
PopularPostLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Linked'
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Website Available' ELSE 'No Website' END AS WebsiteStatus,
    ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TopTags,
    pq.Title AS RecentQuestionTitle,
    pq.CreationDate AS QuestionDate,
    ha.ReputRank,
    qa.AnswerCount,
    qa.AvgAnswerScore,
    qc.CommentCount,
    qc.AvgCommentScore,
    hp.LastHistoryDate,
    hp.PostHistoryTypeId AS LastHistoryType,
    pl.LinkTypeName AS LinkType
FROM Users u
LEFT JOIN Tags t ON t.TagName = ANY(u.Location) -- example, possibly correlating tags with user locations for complexity
LEFT JOIN RecentQuestions pq ON pq.OwnerUserId = u.Id AND pq.RN = 1
LEFT JOIN HighestReputationUsers ha ON ha.UserId = u.Id
LEFT JOIN QuestionAnswers qa ON qa.QuestionId = pq.QuestionId
LEFT JOIN PostComments qc ON qc.PostId = pq.QuestionId
LEFT JOIN LatestPostHistory hp ON hp.PostId = pq.QuestionId
LEFT JOIN PopularPostLinks pl ON pl.PostId = pq.QuestionId
WHERE u.Reputation > (
    SELECT AVG(Reputation) FROM Users
)
 AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL)
AND (qa.AnswerCount IS NULL OR qa.AnswerCount >= 1)
AND (qc.CommentCount IS NULL OR qc.CommentCount >= 0)
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, pq.Title, pq.CreationDate, ha.ReputRank, qa.AnswerCount, qa.AvgAnswerScore, qc.CommentCount, qc.AvgCommentScore, hp.LastHistoryDate, hp.PostHistoryTypeId, pl.LinkTypeName;