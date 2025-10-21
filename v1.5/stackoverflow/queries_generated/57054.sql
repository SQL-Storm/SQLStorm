-- {"query": "57054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1764} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.Title, '') AS Title,
        COALESCE(p.Tags, '') AS Tags,
        COALESCE(p.Body, '') AS Body,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1, 2)
),
TopPosts AS (
    SELECT
        PostId,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        OwnerUserId,
        AnswerCount,
        CommentCount,
        FavoriteCount,
        Title,
        Tags,
        Body
    FROM
        RankedPosts
    WHERE
        Rank <= 5
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(p.PostId, 0) AS LastPostId,
        COALESCE(p.CreationDate, u.CreationDate) AS LastPostDate,
        COALESCE(v.PostId, 0) AS LastVotePostId,
        COALESCE(v.CreationDate, u.CreationDate) AS LastVoteDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        u.Reputation > 1000
),
ActiveTags AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count,
        COALESCE(EXTRACT(EPOCH FROM (NOW() - p.LastActivityDate)), 0) AS DaysSinceLastActivity,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId
    FROM
        Tags t
    JOIN
        Posts p ON t.TagName = ANY(STRING_TO_ARRAY(p.Tags, '><'))
    WHERE
        p.PostTypeId = 1
),
HighActivityUsers AS (
    SELECT
        u.UserId,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.UserId
    HAVING
        PostCount > 10 OR CommentCount > 50 OR VoteCount > 100
), View_Uses AS (
    SELECT
            ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.AccountId) as ROW1,
            ROW_NUMBER() OVER (PARTITION BY u.AccountId ORDER BY Abd.userId) as ROW2,
            U.Id,
            DisplayName,
            Reputation,
            location,
            (select count(*) from Votes where votes.userID=u.id) as VoteCount,
            (select count(*) from Posts where Posts.OwnerUserId = u.id) as NumberOfPosts,
            Views, Upvotes, Downvotes,
            (select array_agg( Abd.Name) from Badges Abd where Abd.UserId=U.Id and Abd.tagbased) as BadgeNames,
            (case when (select all Array_AGG(urel.class) from badges urel where u.id=urel.userid and urel.class!=3)!=ALL(Badges.class) then 1 else 0 end) as BronzeBadgesComplete
    from Users U
    where Reputation>=50 and Reputation <1000 and U.id in (SELECT UserId FROM Badges GROUP BY UserId HAVING COUNT(*) > 20) order by Reputation desc
),
AnswersWithComments AS (
    SELECT
        P1.Id AS PostId,
        CT.Text as Comment,
        UserId,
        CommentCount,
        DisplayName
    FROM
        Posts p1
        JOIN Comments ct on ct.PostId=p1.Id
        JOIN Users U1 on u1.id=p1.UserId
    WHERE
        p1.PostTypeId=2 and AnswerCount > 0 and CommentCount > 0 and CreationDate > NOW() - INTERVAL '1 month'
    ORDER BY CommentCount desc, OwnerUserId desc
)
select u.*, coalesce(ao.PostId,0) as TopAnswer, numeric_stats. UpvotedAnswersComp, numeric_stats.AnsweredQuestionsComp, Coalesce(Philip.TopAnswerBody,array['']) as TopAnswer
from view_uses u
join Lateral (SELECT AnswersWithComments.UserId as UserId, AnswersWithComments.PostId, COUNT(AnswersWithComments.Comment) as CommentsToAnswers
from AnswersWithComments
where AnswersWithComments.UserId=u.id
group by AnswersWithComments.UserId, PostId
ORDER BY CommentsToAnswers DESC LIMIT 5
) ao on u.id=ao.userid
join lateral(
select  username,
COUNT(DISTINCT (select vt2_gets.* from Posts as VT2_gets WHERE vt2_gets.OwnerUserId=AO2.UserId and vt2_gets.PostTypeID=2 and AO2.PostID!=vt2_gets.id and vt2_gets.ID=UP1.PostID)) as AnsweredQuestionsComp,
COUNT(DISTINCT case when (Vp groupex.Id is not null) then (select case when vp_inner.UserId = ao2.UserId then 1 else 0 end from votes as vp_inner where vp_inner.USERid=ao2.UserID and vp_inner.postid=ao2.postid) else 1 end )  as UpvotedAnswersComp from Users as AO2 where AO2.Id=u.Id
group by username
) as numeric_stats on Numeric_Stats.username=u.id

JOIN Lateral (Select PostId, Posts.body as TopAnswerBody from Posts
JOIN users on users.id=posts.OwnerUserId where Posts.Posttypeid=2 and users.id=ao.userid
ORDER BY U.Upvotes desc limit 1
) as Philip on U.id=ao.UserId;

