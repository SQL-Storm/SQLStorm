-- {"query": "646.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1368} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT 
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        parent.Level + 1,
        parent.TagPath || child.TagName
    FROM Tags child
    JOIN Posts p ON p.Tags LIKE '%' || '<' || child.TagName || '>' || '%'
    JOIN RecursiveTagHierarchy parent ON parent.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))
    WHERE child.IsRequired = 0
),
UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END), 0) AS TagBasedBadges,
        u.Reputation,
        u.CreationDate,
        u.Location
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
PostActivityWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        MAX(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS MaxUserViewCount
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2) -- questions and answers
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
CorrelatedSubqueries AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
        (SELECT MIN(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 1) AS FirstTitleEditDate,
        (SELECT STRING_AGG(DISTINCT ph.Comment, '; ' ORDER BY ph.CreationDate) 
         FROM PostHistory ph 
         WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11)) AS CloseReopenComments
    FROM Posts p
    WHERE p.PostTypeId = 1
),
DuplicatesAndLinks AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        pt1.Title AS PostTitle,
        pt2.Title AS RelatedPostTitle,
        CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END AS IsDuplicateLink
    FROM PostLinks pl
    LEFT JOIN Posts pt1 ON pt1.Id = pl.PostId
    LEFT JOIN Posts pt2 ON pt2.Id = pl.RelatedPostId
),
CombinedData AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        u.DisplayName,
        u.Reputation,
        u.Location,
        ua.UserPostRank,
        ua.AvgUserScore,
        ua.MaxUserViewCount,
        cs.UpVotes,
        cs.DownVotes,
        cs.FirstTitleEditDate,
        cs.CloseReopenComments,
        dup.IsDuplicateLink,
        dup.RelatedPostTitle,
        rh.Level AS TagHierarchyLevel,
        rh.TagPath
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN PostActivityWindow ua ON ua.Id = p.Id
    LEFT JOIN CorrelatedSubqueries cs ON cs.PostId = p.Id
    LEFT JOIN DuplicatesAndLinks dup ON dup.PostId = p.Id AND dup.IsDuplicateLink = 1
    LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))
    WHERE p.PostTypeId = 1
)
SELECT 
    cd.Id AS QuestionId,
    cd.Title,
    cd.DisplayName AS Owner,
    cd.Reputation,
    cd.Location,
    cd.UserPostRank,
    cd.AvgUserScore,
    cd.MaxUserViewCount,
    cd.UpVotes,
    cd.DownVotes,
    COALESCE(cd.FirstTitleEditDate, cd.CreationDate) AS FirstTitleEditDate,
    cd.CloseReopenComments,
    cd.IsDuplicateLink,
    cd.RelatedPostTitle,
    cd.TagHierarchyLevel,
    array_to_string(cd.TagPath, ' > ') AS FullTagHierarchyPath,
    LENGTH(cd.Title) - LENGTH(REPLACE(cd.Title, ' ', '')) + 1 AS TitleWordCount,
    CASE 
        WHEN cd.UpVotes + cd.DownVotes = 0 THEN NULL
        ELSE ROUND(cd.UpVotes::numeric / NULLIF(cd.UpVotes + cd.DownVotes, 0), 4)
    END AS UpvoteRatio,
    CASE 
        WHEN cd.Reputation > 10000 THEN 'HighRep'
        WHEN cd.Reputation BETWEEN 1000 AND 10000 THEN 'MidRep'
        ELSE 'LowRep'
    END AS ReputationCategory
FROM CombinedData cd
WHERE cd.UpVotes > 10
  AND (cd.CloseReopenComments IS NULL OR cd.CloseReopenComments NOT LIKE '%Duplicate%')
ORDER BY cd.UpvoteRatio DESC NULLS LAST, cd.UserPostRank ASC
LIMIT 100;
