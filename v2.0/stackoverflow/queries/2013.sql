-- {"query": "2013.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1412}
WITH RECURSIVE RecursivePostsCTE AS (
    SELECT p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.OwnerUserId,
           1 AS Level,
           COALESCE(p.Score * 1.0 / NULLIF(p.ViewCount, 0), 0) AS ScoreViewRatio
    FROM Posts p
    WHERE p.PostTypeId = 1
    UNION ALL
    SELECT p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.OwnerUserId,
           rp.Level + 1 AS Level,
           COALESCE(p.Score * 1.0 / NULLIF(p.ViewCount, 0), 0) AS ScoreViewRatio
    FROM Posts p
    INNER JOIN RecursivePostsCTE rp ON p.ParentId = rp.Id
    WHERE p.PostTypeId = 2
),
RankedAnswers AS (
    SELECT rp.Id, rp.PostTypeId, rp.AcceptedAnswerId, rp.ParentId, rp.CreationDate, rp.Score, rp.ViewCount, rp.Title, rp.OwnerUserId,
           rp.Level, rp.ScoreViewRatio,
           row_number() OVER (PARTITION BY rp.ParentId ORDER BY rp.Score DESC, rp.CreationDate ASC) AS AnswerRank,
           count(*) OVER (PARTITION BY rp.ParentId) AS TotalAnswers
    FROM RecursivePostsCTE rp
    WHERE rp.PostTypeId = 2
),
UserPostStats AS (
    SELECT u.Id AS UserId, u.DisplayName,
           count(distinct CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
           count(distinct CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
           sum(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
           sum(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount,
           avg(COALESCE(p.Score, 0)) AS AvgPostScore,
           max(p.Score) AS MaxPostScore,
           min(p.Score) AS MinPostScore,
           bool_or(p.ClosedDate IS NOT NULL) AS HasClosedPosts
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),
TopCommenters AS (
    SELECT c.UserId, u.DisplayName, count(*) AS CommentCount
    FROM Comments c
    JOIN Users u ON u.Id = c.UserId
    GROUP BY c.UserId, u.DisplayName
    HAVING count(*) > 10
),
PostWithLatestHistory AS (
    SELECT ph.PostId, ph.UserId, ph.PostHistoryTypeId, ph.CreationDate,
           row_number() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
),
LatestPostHistoryFiltered AS (
    SELECT ph.PostId, ph.UserId, ph.PostHistoryTypeId, ph.CreationDate
    FROM PostWithLatestHistory ph
    WHERE ph.rn = 1
),
PostsWithLinks AS (
    SELECT pl.PostId, pl.RelatedPostId, lt.Name AS LinkTypeName,
           p1.CreationDate AS PostCreation,
           p2.CreationDate AS RelatedPostCreation
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
),
QuestionsWithDuplicateAnswers AS (
    SELECT p.Id AS QuestionId, p.Title, count(distinct la.Id) AS DuplicateAnswerCount
    FROM Posts p
    LEFT JOIN Posts la ON la.ParentId = p.Id AND la.Score > 10
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id, p.Title
    HAVING count(distinct la.Id) > 2
)
SELECT u.DisplayName AS UserDisplayName,
       ups.QuestionCount,
       ups.AnswerCount,
       ups.UpVotesCount,
       ups.DownVotesCount,
       ups.AvgPostScore,
       ups.MaxPostScore,
       ups.MinPostScore,
       CASE WHEN ups.HasClosedPosts THEN 'Yes' ELSE 'No' END AS HasClosedPosts,
       COALESCE(tc.CommentCount, 0) AS CommentsMade,
       COALESCE(qwa.DuplicateAnswerCount, 0) AS DuplicateAnswerCount,
       string_agg(DISTINCT COALESCE(pt.Name, 'Unknown'), ', ') AS PostTypesOwned,
       avg(rp.ScoreViewRatio) AS AverageScoreViewRatio,
       lmph.PostHistoryTypeId AS LatestPostHistoryType,
       limt.Name AS LatestPostHistoryTypeName,
       COALESCE(pl.LinkTypeName, 'No Link') AS SampleLinkTypeName,
       COALESCE(pt_inner.Name, 'No Link') AS LinkTypeFullName
FROM UserPostStats ups
JOIN Users u ON u.Id = ups.UserId
LEFT JOIN TopCommenters tc ON tc.UserId = u.Id
LEFT JOIN (
    SELECT OwnerUserId, count(distinct PostTypeId) AS DistinctPostTypesCount, string_agg(distinct Pt.Name, ', ') AS Name
    FROM Posts p
    JOIN PostTypes Pt ON Pt.Id = p.PostTypeId
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId > 0
    GROUP BY OwnerUserId
) pt ON pt.OwnerUserId = u.Id
LEFT JOIN RecursivePostsCTE rp ON rp.OwnerUserId = u.Id AND rp.Level = 1
LEFT JOIN LatestPostHistoryFiltered lmph ON lmph.UserId = u.Id
LEFT JOIN PostHistoryTypes limt ON limt.Id = lmph.PostHistoryTypeId
LEFT JOIN PostsWithLinks pl ON pl.PostId = (
    SELECT min(Id) FROM Posts WHERE OwnerUserId = u.Id AND Id IS NOT NULL
)
LEFT JOIN QuestionsWithDuplicateAnswers qwa ON qwa.QuestionId = (
    SELECT min(Id) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1
)
LEFT JOIN PostTypes pt_inner ON pt_inner.Id = (
    SELECT p2.PostTypeId FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId IS NOT NULL ORDER BY p2.Id LIMIT 1
)
WHERE (ups.QuestionCount + ups.AnswerCount) > 5
GROUP BY u.DisplayName, ups.QuestionCount, ups.AnswerCount, ups.UpVotesCount, ups.DownVotesCount,
         ups.AvgPostScore, ups.MaxPostScore, ups.MinPostScore, ups.HasClosedPosts,
         tc.CommentCount, qwa.DuplicateAnswerCount, lmph.PostHistoryTypeId, limt.Name,
         COALESCE(pl.LinkTypeName, 'No Link'), COALESCE(pt_inner.Name, 'No Link'), u.Id
ORDER BY ups.UpVotesCount DESC, AverageScoreViewRatio DESC
LIMIT 50;