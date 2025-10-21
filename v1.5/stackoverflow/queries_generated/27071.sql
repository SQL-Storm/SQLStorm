-- {"query": "27071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1250} 

WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.LastAccessDate,
        COUNT(p.Id) AS PostCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(v.VoteTypeId = 2) AS UpVotesGiven,
        SUM(v.VoteTypeId = 3) AS DownVotesGiven
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate > NOW() - INTERVAL '30 days'
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate
),
PostStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCountWithDetails,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.OwnerUserId, u.DisplayName
),
TaggedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS TagRank
    FROM
        Posts p
    LEFT JOIN
        Tags t ON string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), ''><'' ) @> ARRAY[t.TagName]
),
ComplexMetrics AS (
    SELECT
        au.UserId,
        au.DisplayName,
        au.PostCount,
        au.BadgeCount,
        au.UpVotesGiven,
        au.DownVotesGiven,
        ps.PostId,
        ps.PostTypeId,
        ps.CreationDate,
        ps.Score,
        ps.ViewCount,
        ps.OwnerDisplayName,
        ps.CommentCountWithDetails,
        ps.VoteCount,
        ps.UpVotes,
        ps.DownVotes,
        ps.PostRank,
        tp.TagName,
        tp.TagCount,
        tp.TagRank
    FROM
        ActiveUsers au
    JOIN
        PostStats ps ON au.UserId = ps.OwnerUserId
    LEFT JOIN
        TaggedPosts tp ON ps.PostId = tp.PostId
    WHERE
        ps.PostRank <= 5
        AND (tp.TagRank IS NULL OR tp.TagRank <= 3)
        AND (ps.UpVotes >= 5 OR ps.DownVotes = 0)
)
SELECT
    cm.UserId,
    cm.DisplayName,
    cm.PostCount,
    cm.BadgeCount,
    cm.UpVotesGiven,
    cm.DownVotesGiven,
    cm.PostId,
    cm.PostTypeId,
    cm.CreationDate,
    cm.Score,
    cm.ViewCount,
    cm.OwnerDisplayName,
    cm.CommentCountWithDetails,
    cm.VoteCount,
    cm.UpVotes,
    cm.DownVotes,
    cm.PostRank,
    cm.TagName,
    cm.TagCount,
    cm.TagRank
FROM
    ComplexMetrics cm
WHERE EXISTS (
SELECT 1
FROM PostHistory ph
WHERE ph.PostId = cm.PostId AND ph.PostHistoryTypeId IN (2,3,4)
) or
    cm.TagName
    IS DISTINCT FROM 'sql'
ORDER BY
    cm.PostRank,
    cm.TagRank,
    cm.Score DESC,
    cm.UserId,
    cm.PostId;
