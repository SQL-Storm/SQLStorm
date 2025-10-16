-- {"query": "27091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1696} 

WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(p.Id) AS PostCount,
        COUNT(v.Id) AS VoteCount,
        COUNT(c.Id) AS CommentCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    WHERE
        u.LastAccessDate > NOW() - INTERVAL '30 days'
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
), HighActivityPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.ClosedDate, '1970-01-01'::timestamp) AS ClosedDate,
        COALESCE(p.CommunityOwnedDate, '1970-01-01'::timestamp) AS CommunityOwnedDate,
        COUNT(v.Id) AS VoteCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(ph.Id) AS EditCount,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyAmount,
        CASE WHEN LENGTH(p.Tags) > 50 THEN 'ManyTags' ELSE 'FewTags'
        END AS TagCategory
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.ContentLicense
), PopularTags AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        COUNT(p.Id) AS PostCount
    FROM
        Tags t
    LEFT JOIN
        Posts p ON t.TagName = ANY(regexp_split_to_array(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2)), ''><''))
    GROUP BY
        t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired
), UserActivityRank AS (
    SELECT
        UserId,
        Reputation,
        PostCount,
        VoteCount,
        CommentCount,
        RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank,
        RANK() OVER (ORDER BY PostCount DESC) AS PostCountRank,
        RANK() OVER (ORDER BY VoteCount DESC) AS VoteCountRank,
        RANK() OVER (ORDER BY CommentCount DESC) AS CommentCountRank
    FROM
        ActiveUsers
)
SELECT
    uar.UserId,
    uar.Reputation,
    uar.ReputationRank,
    uar.PostCount,
    uar.PostCountRank,
    uar.VoteCount,
    uar.VoteCountRank,
    uar.CommentCount,
    uar.CommentCountRank,
    COALESCE(SUM(hap.Score), 0) AS TotalPostScore,
	COUNT(hap.CommentCount) OVER (PARTITION BY hap.PostId ) ORDER BY hap.ViewCount DESC)   AS CommentRank,
    COALESCE(SUM(hap.BountyAmount), 0) AS TotalBountyAmount,
    COALESCE(MAX(hap.ViewCount), 0) AS MaxViewCount,
    COALESCE(AVG(hap.Score), 0) AS AveragePostScore,
    COALESCE(MIN(hap.CreationDate), '1970-01-01') AS EarliestPostDate,
    COALESCE(MAX(hap.CreationDate), NOW()) AS LatestPostDate,
    COALESCE(MIN(hap.ClosedDate), '1970-01-01') AS EarliestClosedDate,
    COALESCE(MAX(pt.Name), 'Unknown') AS MostCommonPostType,
    COALESCE(ARRAY_TO_STRING(ARRAY_AGG(DISTINCT pt.TagCategory), ', '), 'NoTags') AS CommonTagCategories,
    sub.MostRecentBadgeName,
    sub.MostRecentBadgeDate
FROM
    UserActivityRank uar
LEFT JOIN
    HighActivityPosts hap ON uar.UserId = hap.OwnerUserId
LEFT JOIN
    PostTypes pt ON hap.PostTypeId = pt.Id
LEFT JOIN
   PostHistory ph ON ph.PostId = hap.PostId
LEFT JOIN
    Badges b ON uar.UserId = b.UserId
LEFT JOIN (
        SELECT
            UserId,
            MAX(Date) AS MostRecentBadgeDate,
            (SELECT Name FROM Badges b2 WHERE b2.UserId = b1.UserId AND b2.Date = b1.MostRecentBadgeDate) AS MostRecentBadgeName
        FROM
            Badges b1
        GROUP BY
            UserId
    ) sub ON uar.UserId = sub.UserId
GROUP BY
    uar.UserId, uar.Reputation, uar.ReputationRank, uar.PostCount, uar.PostCountRank, uar.VoteCount,
    uar.VoteCountRank, uar.CommentCount, uar.CommentCountRank, sub.MostRecentBadgeName,
    sub.MostRecentBadgeDate
ORDER BY
    uar.ReputationRank,
    hap.Score DESC
LIMIT 100;
