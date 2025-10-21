-- {"query": "44056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 128464, "output_tokens": 44872} 
Here is an elaborate SQL query for performance benchmarking:

WITH cte AS (
    SELECT
        p.Id,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        u.Reputation,
        u.DisplayName,
        u.Location,
        u.AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.TagBased AS BadgeTagBased,
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
            WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
            WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
        END AS PostType,
        CASE
            WHEN v.VoteTypeId = 1 THEN 'AcceptedByOriginator'
            WHEN v.VoteTypeId = 2 THEN 'UpMod'
            WHEN v.VoteTypeId = 3 THEN 'DownMod'
            WHEN v.VoteTypeId = 4 THEN 'Offensive'
            WHEN v.VoteTypeId = 5 THEN 'Favorite'
            WHEN v.VoteTypeId = 6 THEN 'Close'
            WHEN v.VoteTypeId = 7 THEN 'Reopen'
            WHEN v.VoteTypeId = 8 THEN 'BountyStart'
            WHEN v.VoteTypeId = 9 THEN 'BountyClose'
            WHEN v.VoteTypeId = 10 THEN 'Deletion'
            WHEN v.VoteTypeId = 11 THEN 'Undeletion'
            WHEN v.VoteTypeId = 12 THEN 'Spam'
            WHEN v.VoteTypeId = 14 THEN 'NominateModerator'
            WHEN v.VoteTypeId = 15 THEN 'ModeratorReview'
            WHEN v.VoteTypeId = 16 THEN 'ApproveEditSuggestion'
        END AS VoteType,
        v.BountyAmount,
        v.CreationDate AS VoteCreationDate,
        ph.PostHistoryTypeId,
        ph.Comment AS PostHistoryComment,
        ph.Text AS PostHistoryText,
        ph.CreationDate AS PostHistoryCreationDate,
        ph.UserId AS PostHistoryUserId,
        ph.UserDisplayName AS PostHistoryUserDisplayName,
        pl.LinkTypeId,
        pl.CreationDate AS PostLinkCreationDate,
        pl.RelatedPostId,
        c.Score AS CommentScore,
        c.Text AS CommentText,
        c.CreationDate AS CommentCreationDate,
        c.UserDisplayName AS CommentUserDisplayName
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Tags t ON p.Tags LIKE '%<' + t.TagName + '>%'
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
)
SELECT
    *
FROM cte
ORDER BY CreationDate DESC
LIMIT 10000;