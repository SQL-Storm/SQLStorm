-- {"query": "27009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1827} 

WITH UserStatistics AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS TotalGoldBadges,
        SUM(CASE WHен b.Class = 2 THEN 1 ELSE 0 END) AS TotalSilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS TotalBronzeBadges,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyAmount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
),
PostActivity AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        COUNT(c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS TotalUpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS TotalDownVotes,
        MAX(v.CreationDate) AS LastVoteDate,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PostRank
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.TotalAnswers,
    us.TotalComments,
    us.LastPostDate,
    us.TotalUpVotesReceived,
    us.TotalDownVotesReceived,
    us.TotalGoldBadges,
    us.TotalSilverBadges,
    us.TotalBronzeBadges,
    us.TotalBountyAmount,
    pa.PostId,
    pa.PostTypeId,
    pa.CreationDate,
    pa.Score,
    pa.ViewCount,
    pa.TotalComments,
    pa.TotalVotes,
    pa.TotalUpVotes,
    pa.TotalDownVotes,
    pa.LastVoteDate,
    pa.PreviousScore,
    pa.NextScore,
    pa.PostRank,
    CASE
        WHEN pa.PostTypeId = 1 THEN 'Question'
        WHEN pa.PostTypeId = 2 THEN 'Answer'
        WHEN pa.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN pa.PostTypeId = 5 THEN 'TagWiki'
        ELSE 'Other'
    END AS PostTypeName,
    SUBSTRING(pa.Tags, 2, LENGTH(pa.Tags) - 2) AS CleanedTags,
    STRING_AGG(DISTINCT t.TagName, ', ') AS AllTags,
    COALESCE(t.Count, 0) AS TagCount,
    COALESCE(t.ExcerptPostId, 0) AS ExcerptPostId,
    COALESCE(t.WikiPostId, 0) AS WikiPostId,
    COALESCE(t.IsModeratorOnly, FALSE) AS IsModeratorOnly,
    COALESCE(t.IsRequired, FALSE) AS IsRequired,
    CASE
        WHEN pht.Name IS NOT NULL THEN pht.Name
        ELSE 'Unknown'
    END AS LastPostHistoryType,
    ph.CreationDate AS LastPostHistoryDate,
    ph.Comment AS LastPostHistoryComment,
    lt.Name AS LastLinkType,
    pl.RelatedPostId AS LastRelatedPostId,
    u2.DisplayName AS LastRelatedPostOwner
FROM
    UserStatistics us
JOIN
    PostActivity pa ON us.UserId = pa.OwnerUserId
LEFT JOIN
    Tags t ON pa.Tags LIKE CONCAT('%<', t.TagName, '>%')
LEFT JOIN
    PostHistory ph ON pa.PostId = ph.PostId
LEFT JOIN
    PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN
    PostLinks pl ON pa.PostId = pl.PostId
LEFT JOIN
    LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN
    Users u2 ON pl.RelatedPostId = u2.Id
WHERE
    us.TotalPosts > 10 AND
    pa.CreationDate >= DATEADD(YEAR, -1, GETDATE()) AND
    (pa.TotalUpVotes > 0 OR pa.TotalDownVotes > 0) AND
    (ph.CreationDate IS NOT NULL OR pl.RelatedPostId IS NOT NULL)
GROUP BY
    us.UserId, us.DisplayName, us.Reputation, us.TotalPosts, us.TotalAnswers, us.TotalComments, us.LastPostDate, us.TotalUpVotesReceived, us.TotalDownVotesReceived, us.TotalGoldBadges, us.TotalSilverBadges, us.TotalBronzeBadges, us.TotalBountyAmount,
    pa.PostId, pa.PostTypeId, pa.CreationDate, pa.Score, pa.ViewCount, pa.TotalComments, pa.TotalVotes, pa.TotalUpVotes, pa.TotalDownVotes, pa.LastVoteDate, pa.PreviousScore, pa.NextScore, pa.PostRank,
    t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired,
    pht.Name, ph.CreationDate, ph.Comment, lt.Name, pl.RelatedPostId, u2.DisplayName
ORDER BY
    us.Reputation DESC,
    pa.CreationDate DESC,
    pa.Score DESC;
