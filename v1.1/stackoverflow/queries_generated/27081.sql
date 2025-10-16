-- {"query": "27081.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1704} 

WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.LastAccessDate,
        COALESCE(u.WebsiteUrl, '') AS WebsiteUrl,
        COALESCE(u.Location, '') AS Location,
        COALESCE(u.AboutMe, '') AS AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.ProfileImageUrl,
        u.EmailHash,
        ROW_NUMBER() OVER (PARTITION BY u.AccountId ORDER BY u.LastAccessDate DESC) AS rn
    FROM
        Users u
    WHERE
        u.LastAccessDate >= DATEADD(MONTH, -6, GETDATE())
        AND u.Reputation > 1000
)
, ReputablePosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
		CASE
	    WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id
	    ELSE NULL
	    END AS AcceptedAnswerId,
        COALESCE(p.ParentId, 0) AS ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Body,
        p.OwnerUserId,
        COALESCE(p.OwnerDisplayName, 'Anonymous') AS OwnerDisplayName,
        p.LastEditorUserId,
        COALESCE(p.LastEditorDisplayName, 'Anonymous') AS LastEditorDisplayName,
        p.LastEditDate,
        p.Title,
		p.Tags,
        p.AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        p.LastActivityDate,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate
    FROM
        Posts p
        LEFT JOIN ActiveUsers au
        ON p.OwnerUserId = au.UserId
    WHERE
        p.PostTypeId IN (1, 2)
        AND p.CreationDate >= DATEADD(YEAR, -2, GETDATE())
        AND (p.Score > 5 OR p.ViewCount > 100)
)
, HighActivityComments AS (
    SELECT
        Id,
        COMMENTS.PostId,
        Score,
        CreationDate,
        CASE
        WHEN USERS.UserId is NULL THEN 'Guest'
        WHEN LEN(UserDisplayName) > 1 THEN UserDisplayName
		ELSE "No name"
        END,
        UserId,
        UserDisplayName,
		ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS Rank
    FROM Comments
    LEFT JOIN Users on Comments.UserId = Users.Id
    WHERE UPPER(TEXT) LIKE '%sql%' OR UPPER(TEXT) LIKE '%heapify%'
    AND LEN(UserDisplayName) > 1
)
, TagInfo AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count,
		COALESCE(t.ExcerptPostId, 0) AS ExcerptPostId,
        COALESCE(t.WikiPostId, 0) AS WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        EXTRACTVALUE(XMLTYPE('<root><vals>' || REPLACE(Turntable.Comments, '|', '</vals><vals>' ) || '</vals></root>'), '/root/vals[1]') AS TagCommentInfo
    FROM
        Tags t, Posts Turntable
)
, PostVotes AS (
    SELECT
        v.Id AS VoteId,
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount,
        CASE
        WHEN v.VoteTypeId = 1 THEN "Accepted by original user"
		WHEN VoteTypeId = 2 THEN "Upvote"
		WHEN VoteTypeId = 3 THEN "Downvote"
        WHEN v.VoteTypeId = 14 THEN "Considered for moderation"
        WHEN v.VoteTypeId NOT IN (1, 2, 3, 14) THEN "Other types"
        ELSE NULL
        END
    FROM
        Votes v
    WHERE
        v.CreationDate >= DATEADD(MONTH, -6, GETDATE())
)
, PostActivity AS (
    SELECT
        p.PostId,
        p.PostTypeId,
        p.CreationDate,
        STRING_AGG(UserDisplayName, '\')
        OVER (PARTITION BY p.Id  ORDER BY p.CreationDate DESC) AS DomainUser,
		p.CommentCount,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostId ORDER BY p.CreationDate DESC) AS PreviousScore,
        LAG(p.ViewCount, 2) OVER (PARTITION BY p.PostId ORDER BY p.CreationDate DESC) AS TwoDaysAgoViews,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) OVER (PARTITION BY p.PostId) AS MedianChange
    FROM
        ReputablePosts p
        LEFT JOIN HighActivityComments hac
        ON p.PostId = hac.PostId
        LEFT JOIN ActiveUsers au
        ON p.OwnerUserId = au.UserId
    WHERE
     ASCII(SUBSTRING(p.Body, 1, 1)) % 9 != 1
)
SELECT
    pa.PostId,
    pa.PostTypeId,
    pa.CreationDate,
    pa.DomainUser,
    pa.CommentCount,
    pa.PreviousScore,
    pa.TwoDaysAgoViews,
    pa.MedianChange,
    (SELECT
        COUNT(v.VoteId)
    FROM
        PostVotes v
    WHERE
        v.PostId = pa.PostId AND v.VoteTypeId = 2
    ) AS UpvoteCount,
    (SELECT
        COUNT(v.VoteId)
    FROM
        PostVotes v
    WHERE
        v.PostId = pa.PostId AND v.VoteTypeId = 3
    ) AS DownvoteCount,
    ti.TagName
FROM
    PostActivity pa
    JOIN HighActivityComments hac ON pa.PostId = hac.PostId
    OUTER APPLY (SELECT TOP 1 *
    FROM TagInfo
    WHERE CHARINDEX('<tag>',pa.Title) > 0 ) ti
ORDER BY
    pa.CreationDate DESC
OFFSET 20
ROWS
FETCH NEXT
25 ROWS ONLY
    ;