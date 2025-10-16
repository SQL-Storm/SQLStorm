-- {"query": "1336.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1187} 
WITH RecursiveUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS RecentPostRank,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS TotalUpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS TotalDownVotes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE u.Reputation > 1000
),
UserBadgeRanks AS (
    SELECT
        b.UserId,
        b.Name,
        RANK() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM Badges b
    WHERE b.Class = 1
),
LatestGoldBadgeUsers AS (
    SELECT DISTINCT
        ubr.UserId
    FROM UserBadgeRanks ubr
    WHERE ubr.BadgeRank = 1
),
QuestionAnswerInfo AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.Title,
        q.Tags,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ph.Text AS LatestEditSummary,
        ph.CreationDate AS EditDate
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN LATERAL (
        SELECT ph1.Text, ph1.CreationDate
        FROM PostHistory ph1
        WHERE ph1.PostId = a.Id
        ORDER BY ph1.CreationDate DESC
        LIMIT 1
    ) ph ON TRUE
    WHERE q.PostTypeId = 1 AND q.ClosedDate IS NULL
),
TagExplode AS (
    SELECT q.QuestionId, UNNEST(string_to_array(
        substring(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><')) AS Tag
    FROM QuestionAnswerInfo q
),
AnswerStats AS (
    SELECT
        QuestionId,
        AVG(AnswerScore) AS AvgAnswerScore,
        MAX(AnswerScore) AS MaxAnswerScore,
        COUNT(AnswerId) AS AnswerCount
    FROM QuestionAnswerInfo
    GROUP BY QuestionId
),
AnswerersWithBadges AS (
    SELECT DISTINCT aai.AnswerOwnerId 
    FROM QuestionAnswerInfo aai
    JOIN LatestGoldBadgeUsers lgbu ON lgbu.UserId = aai.AnswerOwnerId
    WHERE aai.AnswerScore > 5
),
FinalSelection AS (
    SELECT
        qai.QuestionId,
        qai.Title,
        qai.Tags,
        aas.AvgAnswerScore,
        aas.MaxAnswerScore,
        aas.AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        string_agg(DISTINCT te.Tag, ', ') AS DistinctTags,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ua.Reputation,
        lr.UserId IS NOT NULL AS HasGoldBadge,
        (
            SELECT COUNT(*)
            FROM Votes v2
            WHERE v2.PostId = qai.QuestionId AND v2.VoteTypeId = 2
        ) AS QuestionUpVotes,
        (
            SELECT lh.Comment
            FROM PostHistory lh
            WHERE lh.PostId = qai.QuestionId AND lh.PostHistoryTypeId = 10
            ORDER BY lh.CreationDate DESC
            LIMIT 1
        ) AS LastCloseReason,
        CASE 
            WHEN qai.AnswerScore > 10 THEN 'Top Answer'
            WHEN qai.AnswerScore BETWEEN 5 AND 10 THEN 'Good Answer'
            ELSE 'Standard Answer' 
        END AS AnswerQuality,
        ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY aas.MaxAnswerScore DESC NULLS LAST) AS AnswerRankPerUser
    FROM QuestionAnswerInfo qai
    LEFT JOIN AnswerStats aas ON aas.QuestionId = qai.QuestionId
    LEFT JOIN Comments c ON c.PostId = qai.QuestionId OR c.PostId = qai.AnswerId
    LEFT JOIN TagExplode te ON te.QuestionId = qai.QuestionId
    LEFT JOIN RecursiveUserActivity ua ON ua.UserId = qai.QuestionOwnerId AND ua.PostId = qai.QuestionId
    LEFT JOIN LatestGoldBadgeUsers lr ON lr.UserId = ua.UserId
    GROUP BY 
        qai.QuestionId, qai.Title, qai.Tags, aas.AvgAnswerScore, aas.MaxAnswerScore, aas.AnswerCount,
        ua.TotalUpVotes, ua.TotalDownVotes, ua.Reputation, lr.UserId, qai.AnswerScore
)
SELECT
    fs.QuestionId,
    fs.Title,
    fs.DistinctTags,
    fs.AnswerCount,
    fs.AvgAnswerScore,
    fs.MaxAnswerScore,
    fs.CommentCount,
    fs.TotalUpVotes,
    fs.TotalDownVotes,
    fs.Reputation,
    fs.HasGoldBadge,
    fs.QuestionUpVotes,
    fs.LastCloseReason,
    fs.AnswerQuality,
    fs.AnswerRankPerUser
FROM FinalSelection fs
WHERE fs.AnswerRankPerUser = 1
  AND fs.Reputation > 1500
  AND fs.MaxAnswerScore > 15
ORDER BY fs.MaxAnswerScore DESC, fs.Reputation DESC;