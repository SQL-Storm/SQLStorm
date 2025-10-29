-- {"query": "2410.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1523}
WITH RECURSIVE RecursivePostHierarchy AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        1 AS Level,
        ARRAY[p.Id] AS Path
    FROM Posts p
    WHERE p.PostTypeId = 1
    UNION ALL
    SELECT
        child.Id,
        child.PostTypeId,
        child.ParentId,
        child.AcceptedAnswerId,
        child.OwnerUserId,
        child.CreationDate,
        child.Score,
        child.ViewCount,
        child.Title,
        child.Tags,
        parent.Level + 1 AS Level,
        parent.Path || child.Id
    FROM Posts child
    JOIN RecursivePostHierarchy parent ON parent.Id = child.ParentId
    WHERE child.PostTypeId = 2
), UserBadgesCount AS (
    SELECT 
        b.UserId, 
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
), LatestUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        MAX(ph.CreationDate) AS LastEditDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
), QuestionStats AS (
    SELECT
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        COALESCE(q.AnswerCount, 0) AS AnswerCount,
        COALESCE(q.FavoriteCount, 0) AS FavoriteCount,
        q.AcceptedAnswerId,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVotes,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        q.Tags,
        (SELECT STRING_AGG(DISTINCT lt.Name, ', ') FROM PostLinks pl JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id WHERE pl.PostId = q.Id) AS LinkedPostTypes,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC, q.CreationDate DESC) AS UserTopQuestionRank
    FROM Posts q
    WHERE q.PostTypeId = 1
), ComplexPostRanking AS (
    SELECT
        rph.Id,
        rph.PostTypeId,
        rph.ParentId,
        rph.CreationDate,
        rph.Score,
        rph.ViewCount,
        rph.Level,
        rph.Path,
        qs.Title,
        qs.AnswerCount,
        qs.FavoriteCount,
        qs.UpVotes,
        qs.DownVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        lu.DisplayName,
        lu.Reputation,
        lu.LastAccessDate,
        lu.LastEditDate,
        lu.LastCommentDate,
        (
            rph.Score * 0.7
            + COALESCE(qs.ViewCount, 0) * 0.15
            + COALESCE(qs.AnswerCount, 0) * 3
            + COALESCE(qs.FavoriteCount, 0) * 5
            + COALESCE(ub.GoldBadges, 0) * 10
            + COALESCE(ub.SilverBadges, 0) * 5
            + COALESCE(ub.BronzeBadges, 0) * 2
        ) /
        GREATEST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - rph.CreationDate)) / 86400, 1) AS WeightedScorePerDay,
        qs.IsClosed,
        qs.UserTopQuestionRank,
        rph.Tags,
        rph.OwnerUserId
    FROM RecursivePostHierarchy rph
    LEFT JOIN QuestionStats qs ON qs.Id = CASE WHEN rph.PostTypeId = 2 THEN rph.ParentId ELSE rph.Id END
    LEFT JOIN UserBadgesCount ub ON ub.UserId = rph.OwnerUserId
    LEFT JOIN LatestUserActivity lu ON lu.UserId = rph.OwnerUserId
), FilteredPosts AS (
    SELECT *
    FROM ComplexPostRanking
    WHERE 
        (Tags ILIKE '%<sql>%' OR Tags ILIKE '%<performance>%')
        AND UserTopQuestionRank <= 5
        AND IsClosed = 0
        AND CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years')
        AND (ViewCount > 1000 OR Score > 10)
), DistinctTopPosts AS (
    SELECT DISTINCT ON (OwnerUserId)
        Id, PostTypeId, Title, OwnerUserId, WeightedScorePerDay
    FROM FilteredPosts
    ORDER BY OwnerUserId, WeightedScorePerDay DESC
), UnionedSet AS (
    SELECT OwnerUserId, 'Question' AS PostCategory, Id, Title, WeightedScorePerDay
    FROM DistinctTopPosts
    WHERE PostTypeId = 1
    UNION
    SELECT rph.OwnerUserId, 'Answer' AS PostCategory, rph.Id, rph.Title, rph.WeightedScorePerDay
    FROM FilteredPosts rph
    WHERE rph.PostTypeId = 2 AND rph.Level = 2
), RankedUnion AS (
    SELECT
        us.OwnerUserId,
        us.PostCategory,
        us.Id,
        us.Title,
        us.WeightedScorePerDay,
        RANK() OVER (PARTITION BY us.PostCategory ORDER BY us.WeightedScorePerDay DESC) AS RankByCategory,
        DENSE_RANK() OVER (ORDER BY us.WeightedScorePerDay DESC) AS GlobalRank
    FROM UnionedSet us
)
SELECT
    ru.GlobalRank,
    ru.RankByCategory,
    ru.PostCategory,
    ru.Id AS PostId,
    CASE WHEN LENGTH(ru.Title) > 150 THEN SUBSTRING(ru.Title FROM 1 FOR 150) || '...' ELSE ru.Title END AS ShortTitle,
    ru.WeightedScorePerDay,
    COALESCE(u.DisplayName, 'unknown user') AS OwnerName,
    u.Reputation,
    u.LastAccessDate,
    CASE 
        WHEN u.Reputation > 100000 THEN 'Legend'
        WHEN u.Reputation > 20000 THEN 'Expert'
        WHEN u.Reputation > 5000 THEN 'Intermediate'
        ELSE 'Novice'
    END AS UserLevel
FROM RankedUnion ru
LEFT JOIN Users u ON u.Id = ru.OwnerUserId
WHERE ru.GlobalRank <= 50
ORDER BY ru.GlobalRank;