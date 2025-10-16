-- {"query": "1344.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1121} 

WITH RecursiveUserBadgeCount AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
TopTagUsage AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count,
        p.OwnerUserId,
        COUNT(*) AS QuestionsWithTag
    FROM Tags t
    JOIN Posts p ON p.PostTypeId = 1
        AND POSITION(CONCAT('<', t.TagName, '>') IN COALESCE(p.Tags, '')) > 0
    GROUP BY t.Id, t.TagName, t.Count, p.OwnerUserId
    HAVING t.Count > 1000
),
UserTagParticipation AS (
    SELECT
        tau.OwnerUserId AS UserId,
        tau.TagName,
        tau.QuestionsWithTag,
        RANK() OVER (PARTITION BY tau.OwnerUserId ORDER BY tau.QuestionsWithTag DESC) AS RankByTagUse
    FROM TopTagUsage tau
    WHERE tau.OwnerUserId IS NOT NULL
),
LatestQuestionAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
AggregatedVotes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(*) AS TotalVotes,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
QuestionCloseInfo AS (
    SELECT
        ph.PostId,
        MIN(ph.CreationDate) AS CloseDate,
        COUNT(*) AS CloseCount,
        STRING_AGG(DISTINCT crt.Name, ' | ') AS CloseReasons
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id::text = ph.Comment AND ph.PostHistoryTypeId = 10
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
)
SELECT
    u.DisplayName,
    u.Reputation,
    gu.GoldBadges,
    gu.SilverBadges,
    gu.BronzeBadges,
    utp.TagName AS FavoriteTag,
    lt.QuestionCount,
    lt.AnswerCount,
    qs.Title AS LatestQuestionTitle,
    a.AnswerId AS TopAnswerId,
    a.AnswerUserId,
    a.AnswerScore,
    av.UpVotes,
    av.DownVotes,
    qc.CloseCount,
    qc.CloseReasons,
    CASE 
        WHEN qc.CloseCount > 0 THEN 'Closed'
        ELSE 'Open'
    END AS QuestionStatus,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY a.AnswerScore DESC NULLS LAST) AS AnswerRankForUser
FROM Users u
JOIN RecursiveUserBadgeCount gu ON gu.UserId = u.Id AND gu.BadgeRank <= 100
LEFT JOIN (
    SELECT
        OwnerUserId,
        COUNT(DISTINCT Id) FILTER (WHERE PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT Id) FILTER (WHERE PostTypeId = 2) AS AnswerCount
    FROM Posts
    GROUP BY OwnerUserId
) lt ON lt.OwnerUserId = u.Id
LEFT JOIN LATERAL (
    SELECT utp.TagName, utp.QuestionsWithTag AS QuestionCount
    FROM UserTagParticipation utp
    WHERE utp.UserId = u.Id AND utp.RankByTagUse = 1
    ORDER BY utp.QuestionsWithTag DESC
    LIMIT 1
) utp ON TRUE
LEFT JOIN LatestQuestionAnswers a ON a.AnswerRank = 1 AND a.OwnerUserId = u.Id
LEFT JOIN Posts qs ON qs.Id = a.QuestionId
LEFT JOIN AggregatedVotes av ON av.PostId = a.AnswerId
LEFT JOIN QuestionCloseInfo qc ON qc.PostId = qs.Id
WHERE u.Reputation > (
    SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Reputation) FROM Users
) 
AND (utp.TagName IS NOT NULL OR lt.QuestionCount > 0)
ORDER BY u.Reputation DESC, gu.GoldBadges DESC, a.AnswerScore DESC
LIMIT 200;
