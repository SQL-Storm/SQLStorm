WITH TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS UserRank
    FROM Users u
    WHERE u.Reputation > 1000
),
PostStats AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        AVG(LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<', ''))) AS AvgBodyTags,
        MAX(v.CreationDate) AS LastVoteDate,
        p.Body
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id, p.Body
),
FilteredPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.OwnerUserId,
        p.LastEditorUserId,
        p.ViewCount,
        p.Tags,
        p.Score,
        ps.CommentCount,
        ps.UpVotes,
        ps.DownVotes,
        ps.AvgBodyTags,
        ps.LastVoteDate
    FROM Posts p
    JOIN PostStats ps ON ps.PostId = p.Id
    WHERE p.Score IS NOT NULL
      AND (ps.UpVotes - ps.DownVotes) > (
          SELECT COALESCE(AVG(v2.BountyAmount), 0)
          FROM Votes v2
          WHERE v2.VoteTypeId = 8
      )
),
MainSelect AS (
    SELECT DISTINCT
        fp.Id AS PostId,
        COALESCE(fp.Title, ('Answer to #' || fp.ParentId)) AS TitleOrAnswer,
        SUBSTRING(fp.Body FROM 1 FOR 100) || '...' AS Snippet,
        tu.DisplayName AS TopUser,
        tu.UserRank,
        fp.CommentCount,
        (fp.UpVotes - fp.DownVotes) AS NetVotes,
        EXTRACT(day FROM (TIMESTAMP '2024-10-01 12:34:56' - fp.CreationDate)) AS DaysOld,
        CASE
          WHEN fp.ViewCount > 10000 THEN 'Hot'
          WHEN fp.ViewCount BETWEEN 1000 AND 10000 THEN 'Warm'
          ELSE 'Cold'
        END AS Popularity,
        COALESCE((
          SELECT STRING_AGG(t.TagName, '|')
          FROM (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(fp.Tags FROM 2 FOR (CHAR_LENGTH(fp.Tags) - 2)), '><')) AS token
          ) tag
          JOIN Tags t ON t.TagName = tag.token
        ), '') AS TagList,
        EXISTS (
          SELECT 1
          FROM Badges b
          WHERE b.UserId = fp.OwnerUserId
            AND b.Class = 1
        ) AS HasGoldBadge
    FROM FilteredPosts fp
    LEFT JOIN TopUsers tu ON tu.Id = fp.OwnerUserId
    LEFT JOIN Users u2 ON u2.Id = fp.LastEditorUserId
    WHERE fp.AvgBodyTags > NULLIF(fp.CommentCount, 0)
      AND fp.LastVoteDate > fp.CreationDate
),
NoVotePosts AS (
    SELECT
        p.Id AS PostId,
        p.Title AS TitleOrAnswer,
        CAST(NULL AS TEXT) AS Snippet,
        CAST(NULL AS TEXT) AS TopUser,
        CAST(NULL AS BIGINT) AS UserRank,
        CAST(NULL AS BIGINT) AS CommentCount,
        CAST(NULL AS BIGINT) AS NetVotes,
        CAST(NULL AS DOUBLE PRECISION) AS DaysOld,
        CAST(NULL AS TEXT) AS Popularity,
        CAST(NULL AS TEXT) AS TagList,
        FALSE AS HasGoldBadge
    FROM Posts p
    WHERE NOT EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = p.Id
    )
)
SELECT *
FROM (
    SELECT
        PostId,
        TitleOrAnswer,
        Snippet,
        TopUser,
        UserRank,
        CommentCount,
        NetVotes,
        DaysOld,
        Popularity,
        TagList,
        HasGoldBadge
    FROM MainSelect

    UNION

    SELECT
        PostId,
        TitleOrAnswer,
        Snippet,
        TopUser,
        UserRank,
        CommentCount,
        NetVotes,
        DaysOld,
        Popularity,
        TagList,
        HasGoldBadge
    FROM NoVotePosts

    INTERSECT

    SELECT
        fp2.Id AS PostId,
        COALESCE(fp2.Title, ('Answer to #' || fp2.ParentId)) AS TitleOrAnswer,
        SUBSTRING(fp2.Body FROM 1 FOR 100) || '...' AS Snippet,
        tu2.DisplayName AS TopUser,
        tu2.UserRank,
        fp2.CommentCount,
        (fp2.UpVotes - fp2.DownVotes) AS NetVotes,
        EXTRACT(day FROM (TIMESTAMP '2024-10-01 12:34:56' - fp2.CreationDate)) AS DaysOld,
        CASE
          WHEN fp2.ViewCount > 10000 THEN 'Hot'
          WHEN fp2.ViewCount BETWEEN 1000 AND 10000 THEN 'Warm'
          ELSE 'Cold'
        END AS Popularity,
        COALESCE((
          SELECT STRING_AGG(t.TagName, '|')
          FROM (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(fp2.Tags FROM 2 FOR (CHAR_LENGTH(fp2.Tags) - 2)), '><')) AS token
          ) tag
          JOIN Tags t ON t.TagName = tag.token
        ), '') AS TagList,
        EXISTS (
          SELECT 1
          FROM Badges b
          WHERE b.UserId = fp2.OwnerUserId
            AND b.Class = 1
        ) AS HasGoldBadge
    FROM FilteredPosts fp2
    LEFT JOIN TopUsers tu2 ON tu2.Id = fp2.OwnerUserId
) final
ORDER BY NetVotes DESC NULLS LAST, DaysOld ASC NULLS LAST
LIMIT 100;