-- {"query": "4697.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1075}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        u.DisplayName AS OwnerDisplayName,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.Title IS NOT NULL AND LENGTH(p.Title) > 10
),
QuestionAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) as answer_rank
    FROM Posts q
    JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 AND a.PostTypeId = 2
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(COALESCE(p.Score, 0)) AS AveragePostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 5
),
TagStats AS (
    SELECT
        t.TagName,
        t.Count AS TagPostCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS RelatedPostsWithTag,
        (SELECT AVG(Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS AverageTagScore
    FROM Tags t
    WHERE t.Count > 100
)
SELECT
    rp.PostId,
    rp.Title AS PostTitle,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    qa.AnswerId,
    qa.AnswerScore,
    qa.AnswerCreationDate,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AveragePostScore,
    ts.TagName,
    ts.TagPostCount,
    ts.AverageTagScore,
    CASE WHEN rp.rn <= 5 THEN 'Top_Recent' ELSE 'Other' END AS PostRecencyCategory,
    CASE WHEN qa.answer_rank = 1 THEN 'Best_Answer' ELSE 'Not_Best_Answer' END AS AnswerQuality,
    COALESCE(ua.LastPostDate, DATE '1900-01-01') AS UserLastActivity,
    CASE WHEN ua.LastPostDate IS NULL THEN TRUE
         WHEN rp.PostCreationDate > ua.LastPostDate THEN TRUE ELSE FALSE END AS PostIsNewerThanUserActivity,
    LENGTH(rp.Title) AS TitleLength,
    UPPER(SUBSTRING(rp.Title FROM 1 FOR 3)) AS TitlePrefix,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountForPost,
    (SELECT SUM(Score) FROM Comments c WHERE c.PostId = rp.PostId) AS TotalCommentScore,
    EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) AS IsLinkedAsDuplicate,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rp.PostId AND ph.PostHistoryTypeId = 5) AS BodyEditCount
FROM RankedPosts rp
LEFT JOIN QuestionAnswers qa ON rp.PostId = qa.QuestionId
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN TagStats ts ON (rp.Title LIKE '%' || ts.TagName || '%' OR (CASE WHEN rp.Title IS NULL THEN '' ELSE rp.Title END) LIKE '%' || ts.TagName || '%')
WHERE rp.rn <= 20
  AND (qa.answer_rank IS NULL OR qa.answer_rank <= 3)
  AND ua.AveragePostScore > 5
  AND ts.TagPostCount > 500
GROUP BY
  rp.PostId,
  rp.Title,
  rp.PostTypeName,
  rp.OwnerDisplayName,
  rp.PostCreationDate,
  rp.rn,
  rp.OwnerUserId,
  qa.AnswerId,
  qa.AnswerScore,
  qa.AnswerCreationDate,
  qa.answer_rank,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.AveragePostScore,
  ua.LastPostDate,
  ts.TagName,
  ts.TagPostCount,
  ts.AverageTagScore
ORDER BY rp.PostCreationDate DESC
LIMIT 100;