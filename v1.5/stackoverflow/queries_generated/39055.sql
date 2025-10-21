-- {"query": "39055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2548} 

WITH
RecentQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') AS TagList
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
     AND pt.Name = 'Question'
    WHERE p.CreationDate >= now() - interval '90 days'
),
AnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS AvgAnswerLatency
    FROM RecentQuestions q
    JOIN Posts a
      ON a.ParentId   = q.Id
     AND a.PostTypeId = 2
    GROUP BY q.Id
),
TopTags AS (
    SELECT
        t.Tag,
        COUNT(*) AS QuestionCount
    FROM RecentQuestions q
    CROSS JOIN LATERAL unnest(q.TagList) AS t(Tag)
    GROUP BY t.Tag
    ORDER BY QuestionCount DESC
    LIMIT 10
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= now() - interval '1 year'
    GROUP BY b.UserId
),
UserVoteCounts AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    WHERE v.CreationDate >= now() - interval '1 year'
    GROUP BY v.UserId
),
UserStats AS (
    SELECT
        u.Id           AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(ub.GoldBadges,   0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(uv.UpVotes,      0) AS UpVotes,
        COALESCE(uv.DownVotes,    0) AS DownVotes
    FROM Users u
    LEFT JOIN UserBadgeCounts ub
      ON u.Id = ub.UserId
    LEFT JOIN UserVoteCounts uv
      ON u.Id = uv.UserId
)
SELECT
    tt.Tag,
    COUNT(DISTINCT q.Id)                      AS TotalQuestions,
    SUM(ast.TotalAnswers)                     AS TotalAnswers,
    ROUND(AVG(ast.AvgAnswerLatency) / 3600, 2) AS AvgResponseHours,
    ROUND(AVG(us.Reputation), 0)              AS AvgAuthorReputation,
    SUM(us.GoldBadges)                        AS TotalGoldBadges,
    SUM(us.SilverBadges)                      AS TotalSilverBadges,
    SUM(us.BronzeBadges)                      AS TotalBronzeBadges,
    SUM(us.UpVotes)                           AS SumUpVotes,
    SUM(us.DownVotes)                         AS SumDownVotes
FROM TopTags tt
JOIN RecentQuestions q
  ON tt.Tag = ANY(q.TagList)
JOIN AnswerStats ast
  ON q.Id = ast.QuestionId
JOIN UserStats us
  ON q.OwnerUserId = us.UserId
GROUP BY tt.Tag
ORDER BY TotalQuestions DESC;
