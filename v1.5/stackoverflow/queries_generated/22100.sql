-- {"query": "22100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1296} 
WITH UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, '; ') AS BadgeNames,
        COUNT(CASE WHEN b.TagBased = 1 THEN 1 END) AS TagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND u.LastAccessDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostEditStats AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(p.ClosedDate, '2099-12-31'::timestamp) AS EffectiveCloseDate,
        COUNT(ph.Id) AS TotalEdits,
        MAX(ph.CreationDate) AS LastEditDate,
        STRING_AGG(LEFT(ph.Text, 100), ' | ') AS EditSummaries
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)
    WHERE p.CreationDate BETWEEN '2018-01-01' AND '2022-12-31'
    GROUP BY p.Id, p.Title, p.PostTypeId, p.Score, p.AnswerCount, p.FavoriteCount, p.ClosedDate
),
TopVotedPosts AS (
    SELECT DISTINCT
        PostId,
        COUNT(*) AS TotalVotes,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes,
        AVG(CASE WHEN UserId IS NOT NULL THEN Reputation ELSE NULL END) AS AvgVoterRep
    FROM Votes v
    LEFT JOIN Users u ON v.UserId = u.Id
    GROUP BY PostId
    HAVING COUNT(*) > 10
),
CombinedStats AS (
    SELECT
        ubs.UserId,
        ubs.DisplayName,
        ubs.Reputation,
        ubs.TotalBadges,
        pes.PostId,
        pes.Title,
        pes.Score,
        pes.TotalEdits,
        tvp.TotalVotes,
        tvp.NetVotes,
        tvp.AvgVoterRep,
        CASE WHEN pes.EffectiveCloseDate < CURRENT_TIMESTAMP THEN 1 ELSE 0 END AS IsClosed,
        LENGTH(REPLACE(LOWER(pes.EditSummaries), ' ', '')) AS EditSummaryLength,
        ROW_NUMBER() OVER (PARTITION BY ubs.UserId ORDER BY pes.Score DESC, tvp.NetVotes DESC) AS PostRank
    FROM UserBadgeStats ubs
    LEFT JOIN Posts p ON ubs.UserId = p.OwnerUserId
    LEFT JOIN PostEditStats pes ON p.Id = pes.PostId
    LEFT JOIN TopVotedPosts tvp ON pes.PostId = tvp.PostId
    WHERE pes.Score IS NOT NULL OR tvp.PostId IS NOT NULL
),
TagAnalysis AS (
    SELECT
        PostId,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><')) AS Tag
    FROM Posts
    WHERE PostTypeId = 1 AND Tags IS NOT NULL
),
TagFrequencies AS (
    SELECT
        Tag,
        COUNT(*) AS PostCountWithTag
    FROM TagAnalysis
    GROUP BY Tag
    HAVING COUNT(*) > 100
),
FinalQuery AS (
    SELECT
        cs.UserId,
        cs.DisplayName,
        cs.Reputation,
        cs.TotalBadges,
        cs.PostId,
        cs.Title,
        cs.Score,
        cs.TotalEdits,
        cs.TotalVotes,
        cs.NetVotes,
        cs.AvgVoterRep,
        cs.IsClosed,
        cs.EditSummaryLength,
        cs.PostRank,
        STRING_AGG(tf.Tag, ', ') AS AssociatedTags,
        (cs.Score + COALESCE(cs.NetVotes, 0) + cs.TotalBadges * 10) / NULLIF(POWER(cs.TotalEdits + 1, 0.5), 0) AS ComplexScore
    FROM CombinedStats cs
    LEFT JOIN TagAnalysis ta ON cs.PostId = ta.PostId
    LEFT JOIN TagFrequencies tf ON ta.Tag = tf.Tag
    WHERE cs.PostRank <= 3
    GROUP BY cs.UserId, cs.DisplayName, cs.Reputation, cs.TotalBadges, cs.PostId, cs.Title, cs.Score, cs.TotalEdits, cs.TotalVotes, cs.NetVotes, cs.AvgVoterRep, cs.IsClosed, cs.EditSummaryLength, cs.PostRank
),
UserAggregates AS (
    SELECT
        UserId,
        SUM(ComplexScore) AS TotalComplexScore,
        AVG(CASE WHEN AssociatedTags IS NOT NULL THEN LENGTH(AssociatedTags) ELSE NULL END) AS AvgTagStringLength,
        COUNT(*) AS RankedPosts
    FROM FinalQuery
    GROUP BY UserId
)
SELECT
    fq.UserId,
    fq.DisplayName,
    fq.Reputation,
    fq.TotalBadges,
    fq.PostId,
    fq.Title,
    fq.Score,
    fq.TotalEdits,
    fq.TotalVotes,
    fq.NetVotes,
    fq.AvgVoterRep,
    fq.IsClosed,
    fq.EditSummaryLength,
    fq.PostRank,
    fq.AssociatedTags,
    fq.ComplexScore,
    ua.TotalComplexScore,
    ua.AvgTagStringLength,
    ua.RankedPosts
FROM FinalQuery fq
INNER JOIN UserAggregates ua ON fq.UserId = ua.UserId
WHERE fq.ComplexScore > 0
ORDER BY ua.TotalComplexScore DESC, fq.Reputation DESC
LIMIT 50;