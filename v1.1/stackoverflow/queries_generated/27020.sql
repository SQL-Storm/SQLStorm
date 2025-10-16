-- {"query": "27020.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 2790} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS TotalUpvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS TotalDownvotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        DENSE_RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS PostRank,
        DENSE_RANK() OVER (ORDER BY COUNT(c.Id) DESC) AS CommentRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) DESC) AS UpvoteRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) DESC) AS DownvoteRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeRank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.CreationDate BETWEEN DATEADD(year, -5, GETDATE()) AND GETDATE()
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
), TopUsers AS (
    SELECT
        UserId,
        Reputation,
        DisplayName,
        TotalPostScore,
        TotalPosts,
        TotalComments,
        TotalUpvotes,
        TotalDownvotes,
        TotalBadges,
        PostRank,
        CommentRank,
        UpvoteRank,
        DownvoteRank,
        BadgeRank
    FROM
        UserActivity
    WHERE
        PostRank <= 10 OR
        CommentRank <= 10 OR
        UpvoteRank <= 10 OR
        DownvoteRank <= 10 OR
        BadgeRank <= 10
), TopPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvoteCount,
        COUNT(DISTINCT ph.Id) AS EditCount,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT c.Id) DESC) AS CommentRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT v.Id) DESC) AS VoteRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT ph.Id) DESC) AS EditRank
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Title, p.Tags, u.DisplayName
), PopularPosts AS (
    SELECT
        PostId,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        OwnerUserId,
        Title,
        Tags,
        OwnerDisplayName,
        CommentCount,
        VoteCount,
        UpvoteCount,
        DownvoteCount,
        EditCount,
        ScoreRank,
        ViewRank,
        CommentRank,
        VoteRank,
        EditRank
    FROM
        TopPosts
    WHERE
        ScoreRank <= 10 OR
        ViewRank <= 10 OR
        CommentRank <= 10 OR
        VoteRank <= 10 OR
        EditRank <= 10
), ActiveTags AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT ph.Id) AS TotalEdits,
        DENSE_RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS PostRank,
        DENSE_RANK() OVER (ORDER BY SUM(p.ViewCount) DESC) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY SUM(p.Score) DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT c.Id) DESC) AS CommentRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT v.Id) DESC) AS VoteRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT ph.Id) DESC) AS EditRank
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.Tags LIKE '%<' + t.TagName + '>%'
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.Id, t.TagName
), HotTags AS (
    SELECT
        TagId,
        TagName,
        PostCount,
        TotalViews,
        TotalScore,
        TotalComments,
        TotalVotes,
        TotalEdits,
        PostRank,
        ViewRank,
        ScoreRank,
        CommentRank,
        VoteRank,
        EditRank
    FROM
        ActiveTags
    WHERE
        PostRank <= 10 OR
        ViewRank <= 10 OR
        ScoreRank <= 10 OR
        CommentRank <= 10 OR
        VoteRank <= 10 OR
        EditRank <= 10
), UserInteractions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS InteractedPosts,
        COUNT(DISTINCT c.Id) AS InteractedComments,
        COUNT(DISTINCT v.Id) AS InteractedVotes,
        COUNT(DISTINCT b.Id) AS InteractedBadges,
        COUNT(DISTINCT ph.Id) AS InteractedEdits
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        PostHistory ph ON u.Id = ph.UserId
    GROUP BY
        u.Id, u.DisplayName
), ActiveUsers AS (
    SELECT
        UserId,
        DisplayName,
        InteractedPosts,
        InteractedComments,
        InteractedVotes,
        InteractedBadges,
        InteractedEdits,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostInteractionRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT c.Id) DESC) AS CommentInteractionRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT v.Id) DESC) AS VoteInteractionRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeInteractionRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT ph.Id) DESC) AS EditInteractionRank
    FROM
        UserInteractions
), EngagedUsers AS (
    SELECT
        UserId,
        DisplayName,
        InteractedPosts,
        InteractedComments,
        InteractedVotes,
        InteractedBadges,
        InteractedEdits,
        PostInteractionRank,
        CommentInteractionRank,
        VoteInteractionRank,
        BadgeInteractionRank,
        EditInteractionRank
    FROM
        ActiveUsers
    WHERE
        PostInteractionRank <= 10 OR
        CommentInteractionRank <= 10 OR
        VoteInteractionRank <= 10 OR
        BadgeInteractionRank <= 10 OR
        EditInteractionRank <= 10
)
SELECT
    tu.UserId,
    tu.DisplayName AS TopUser,
    pp.PostId,
    pp.Title AS PopularPost,
    pp.Score,
    pp.ViewCount,
    pp.OwnerDisplayName AS PostOwner,
    ht.TagId,
    ht.TagName AS HotTag,
    eu.DisplayName AS EngagedUser,
    eu.InteractedPosts,
    eu.InteractedComments,
    eu.InteractedVotes,
    eu.InteractedBadges,
    eu.InteractedEdits
FROM
    TopUsers tu
JOIN
    PopularPosts pp ON tu.UserId = pp.OwnerUserId
JOIN
    HotTags ht ON pp.Tags LIKE '%<' + ht.TagName + '>%'
JOIN
    EngagedUsers eu ON tu.UserId = eu.UserId
WHERE
    tu.PostRank = 1 OR
    pp.ScoreRank = 1 OR
    ht.PostRank = 1 OR
    eu.PostInteractionRank = 1
ORDER BY
    tu.UserId, pp.PostId, ht.TagId, eu.UserId;
