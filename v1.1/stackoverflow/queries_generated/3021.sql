-- {"query": "3021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1012} 
WITH UserReputation AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation
),
PostSummaries AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.ContentLicense,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM Posts p
),
EditedPosts AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        STRING_AGG(ph.Comment, ' | ') AS EditComments,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4, 6, 10, 12, 13, 14, 15)) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS EditorCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 6, 10, 12, 13, 14, 15)
    GROUP BY ph.PostId
),
LinkStats AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT l.RelatedPostId) FILTER (WHERE l.LinkTypeId = 1) AS LinkedCount,
        COUNT(DISTINCT l.RelatedPostId) FILTER (WHERE l.LinkTypeId = 3) AS DuplicatedCount
    FROM Posts p
    LEFT JOIN PostLinks l ON p.Id = l.PostId
    GROUP BY p.Id
),
VoteSummary AS (
    SELECT
        p.Id AS PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 1) AND p.PostTypeId = 1 AS AcceptedVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
),
AggregateData AS (
    SELECT
        ps.PostId,
        ps.PostTypeId,
        ps.Title,
        ps.Tags,
        ps.CreationDate,
        ps.OwnerUserId,
        ur.Reputation,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        es.LastEditDate,
        es.EditComments,
        es.EditCount,
        es.EditorCount,
        ls.LinkedCount,
        ls.DuplicatedCount,
        vs.UpVotes,
        vs.DownVotes,
        vs.AcceptedVotes,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.LastActivityDate,
        ps.ContentLicense,
        CASE WHEN ps.PostTypeId = 1 THEN UNNEST(string_to_array(substring(ps.Tags from 2 for length(ps.Tags)-2), '><')) ELSE NULL END AS Tag
    FROM PostSummaries ps
    LEFT JOIN UserReputation ur ON ps.OwnerUserId = ur.UserId
    LEFT JOIN EditedPosts es ON ps.PostId = es.PostId
    LEFT JOIN LinkStats ls ON ps.PostId = ls.PostId
    LEFT JOIN VoteSummary vs ON ps.PostId = vs.PostId
)
SELECT
    *,
    COUNT(*) OVER () AS TotalPosts,
    COUNT(DISTINCT CASE WHEN PostCategory = 'Question' THEN PostId END) OVER () AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN PostCategory = 'Answer' THEN PostId END) OVER () AS TotalAnswers
FROM AggregateData
WHERE
    (Reputation IS NULL OR Reputation >= 0)
    AND (LastEditDate IS NULL OR LastEditDate >= NOW() - INTERVAL '30 days')
    AND (LinkedCount IS NULL OR LinkedCount >= 0)
    AND (DuplicatedCount IS NULL OR DuplicatedCount >= 0)
    AND (UpVotes + DownVotes) > 0
ORDER BY
    LastActivityDate DESC NULLS LAST
LIMIT 100;