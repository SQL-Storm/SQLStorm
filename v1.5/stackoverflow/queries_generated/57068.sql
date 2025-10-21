-- {"query": "57068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 901} 

WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
), HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        PostCount,
        CommentCount,
        VoteCount
    FROM
        ActiveUsers
    WHERE
        Reputation >= 1000
), InfluentialPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        u.DisplayName AS OwnerDisplayName,
        t.TagName,
        COUNT(v.Id) AS VoteCount,
        COUNT(c.Id) AS TotalComments
    FROM
        Posts p
    JOIN
        HighReputationUsers u ON p.OwnerUserId = u.UserId
    JOIN
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, u.DisplayName, t.TagName
), PopularTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS TagUsageCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews
    FROM
        Posts p
    JOIN
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName
    ORDER BY
        TagUsageCount DESC, TotalScore DESC, TotalViews DESC
    LIMIT 20
)
SELECT
    ip.PostId,
    ip.PostTypeId,
    ip.PostCreationDate,
    ip.Score,
    ip.ViewCount,
    ip.AnswerCount,
    ip.CommentCount,
    ip.FavoriteCount,
    ip.OwnerDisplayName,
    ip.TagName,
    ip.VoteCount,
    ip.TotalComments,
    pt.Name AS PopularTagName,
    pt.TagUsageCount,
    pt.TotalScore,
    pt.TotalViews
FROM
    InfluentialPosts ip
JOIN
    PopularTags pt ON ip.TagName = pt.TagName
ORDER BY
    ip.Score DESC, ip.ViewCount DESC, ip.AnswerCount DESC, ip.CommentCount DESC;
