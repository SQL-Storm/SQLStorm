-- {"query": "34055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 900} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id, t.TagName, t.Count, 1 AS Depth, ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsRequired = 0 AND t.IsModeratorOnly = 0
    UNION ALL
    SELECT 
        t2.Id, t2.TagName, t2.Count, rh.Depth + 1, rh.TagPath || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy rh ON t2.Id <> rh.Id
    WHERE rh.Depth < 3 
      AND NOT t2.TagName = ANY(rh.TagPath)
),
EligibleUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate
    FROM Users u
    WHERE u.Reputation > 5000 AND u.CreationDate < NOW() - INTERVAL '2 years'
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionsWithTopAnswers AS (
    SELECT 
        q.Id AS QuestionId, q.Title, q.CreationDate AS QuestionCreation, q.ViewCount, q.Score AS QuestionScore,
        ua.Id AS AnswerId, ua.Score AS AnswerScore, ua.CreationDate AS AnswerCreation,
        us.Id AS AnswererId, us.DisplayName AS AnswererName, us.Reputation AS AnswererRep
    FROM Posts q
    JOIN Posts ua ON ua.ParentId = q.Id AND ua.PostTypeId = 2
    JOIN (
        SELECT ParentId, MAX(Score) AS MaxScore
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) maxa ON maxa.ParentId = q.Id AND ua.Score = maxa.MaxScore
    JOIN Users us ON ua.OwnerUserId = us.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate > NOW() - INTERVAL '6 months'
      AND q.Score >= 5
),
VotesSummary AS (
    SELECT 
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id
),
RecentActivity AS (
    SELECT 
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY ph.PostId
)
SELECT 
    q.QuestionId, q.Title, q.QuestionCreation, q.ViewCount, q.QuestionScore,
    a.AnswerId, a.AnswerScore, a.AnswerCreation,
    a.AnswererId, a.AnswererName, a.AnswererRep,
    vb.UpVotes, vb.DownVotes, vb.TotalBounty,
    ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges,
    ra.EditCount, ra.UniqueEditors, ra.LastEdit
FROM QuestionsWithTopAnswers q
JOIN VotesSummary vb ON vb.PostId = q.QuestionId
JOIN UserBadges ua ON ua.UserId = q.AnswererId
LEFT JOIN RecentActivity ra ON ra.PostId = q.QuestionId
JOIN EligibleUsers eu ON eu.Id = q.AnswererId
WHERE ra.EditCount IS NOT NULL
ORDER BY (vb.UpVotes - vb.DownVotes) DESC, ra.EditCount DESC
LIMIT 100;
