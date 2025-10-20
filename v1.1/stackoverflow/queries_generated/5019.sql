-- {"query": "5019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 950} 
WITH RecentActiveQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        p.LastActivityDate,
        COALESCE(p.AnswerCount, 0) AS AnswerCount
    FROM Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= NOW() - INTERVAL '90 days'
        AND p.Score > 0
),
TopContributors AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionsAsked,
        COUNT(DISTINCT a.Id) AS AnswersGiven
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    WHERE u.CreationDate <= NOW() - INTERVAL '180 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 2 AND COUNT(DISTINCT a.Id) >= 5
),
AnswerEngagement AS (
    SELECT
        q.QuestionId,
        COUNT(a.Id) AS NumAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS MostRecentAnswerDate
    FROM RecentActiveQuestions q
    LEFT JOIN Posts a ON a.ParentId = q.QuestionId AND a.PostTypeId = 2
    GROUP BY q.QuestionId
),
VotesAgg AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites
    FROM Votes v
    WHERE v.CreationDate >= NOW() - INTERVAL '90 days'
    GROUP BY v.PostId
)
SELECT
    q.QuestionId,
    q.Title,
    u.DisplayName AS AskerName,
    u.Reputation AS AskerReputation,
    COALESCE(ve.UpVotes, 0) AS UpVotes,
    COALESCE(ve.DownVotes, 0) AS DownVotes,
    COALESCE(ve.Favorites, 0) AS Favorites,
    q.ViewCount,
    q.AnswerCount,
    aeng.NumAnswers,
    aeng.AvgAnswerScore,
    aeng.MostRecentAnswerDate,
    ts.TagList,
    CASE 
        WHEN q.AnswerCount = 0 THEN 'Unanswered'
        WHEN aeng.AvgAnswerScore IS NULL THEN 'Needs Review'
        ELSE 'Active'
    END AS EngagementStatus,
    RANK() OVER (ORDER BY COALESCE(ve.UpVotes,0) + COALESCE(ve.Favorites,0) DESC, q.ViewCount DESC) AS PopularityRank,
    b.BadgeCount
FROM RecentActiveQuestions q
LEFT JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN VotesAgg ve ON ve.PostId = q.QuestionId
LEFT JOIN AnswerEngagement aeng ON aeng.QuestionId = q.QuestionId
LEFT JOIN (
    SELECT
        p.Id,
        string_agg(tag, ', ') AS TagList
    FROM (
        SELECT
            Id,
            unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS tag
        FROM Posts
        WHERE PostTypeId = 1
    ) p
    GROUP BY p.Id
) ts ON ts.Id = q.QuestionId
LEFT JOIN (
    SELECT
        b.UserId,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
) b ON b.UserId = q.OwnerUserId
WHERE (COALESCE(ve.UpVotes,0) - COALESCE(ve.DownVotes,0) > 2 OR aeng.AvgAnswerScore > 0)
  AND (
      q.OwnerUserId IN (SELECT UserId FROM TopContributors)
      OR (q.ViewCount > 1000 AND q.Score >= 5)
  )
ORDER BY PopularityRank
FETCH FIRST 50 ROWS ONLY;