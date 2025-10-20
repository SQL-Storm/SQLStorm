-- {"query": "948.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1150} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.CreationDate,
        array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) as TagCount,
        row_number() over (partition by t.Id order by p.Score desc, p.CreationDate asc) as rn
    from
        Tags t
        left join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    where
        p.PostTypeId = 1 -- questions only
),
FilteredTopPosts as (
    select
        Id,
        TagName,
        Count,
        PostId,
        Score,
        CreationDate,
        TagCount
    from
        RecursiveTagCounts
    where
        rn <= 5
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(pq.QuestionsAsked, 0) as QuestionsAsked,
        coalesce(pa.AnswersCount, 0) as AnswersGiven,
        coalesce(cmt.CommentsMade, 0) as CommentsMade,
        coalesce(bdg.BadgesEarned, 0) as BadgesEarned,
        coalesce(vt.UpVotes, 0) as UpVotesCast,
        coalesce(vt.DownVotes, 0) as DownVotesCast,
        rank() over (order by u.Reputation desc, QuestionsAsked desc) as UserRank
    from
        Users u
        left join (
            select OwnerUserId, count(*) as QuestionsAsked
            from Posts
            where PostTypeId = 1 and OwnerUserId is not null
            group by OwnerUserId
        ) pq on pq.OwnerUserId = u.Id
        left join (
            select OwnerUserId, count(*) as AnswersCount
            from Posts
            where PostTypeId = 2 and OwnerUserId is not null
            group by OwnerUserId
        ) pa on pa.OwnerUserId = u.Id
        left join (
            select UserId, count(*) as CommentsMade
            from Comments
            group by UserId
        ) cmt on cmt.UserId = u.Id
        left join (
            select UserId, count(*) as BadgesEarned
            from Badges
            group by UserId
        ) bdg on bdg.UserId = u.Id
        left join (
            select UserId,
                sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
                sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
            from Votes
            where UserId is not null
            group by UserId
        ) vt on vt.UserId = u.Id
),
PostLinksInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        count(*) over (partition by pl.PostId) as LinkCountPerPost
    from
        PostLinks pl
        join LinkTypes lt on pl.LinkTypeId = lt.Id
),
UserTopPosts as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.UserRank,
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        pl.LinkTypeName,
        pl.LinkCountPerPost,
        row_number() over (partition by ua.UserId order by p.Score desc) as rn
    from
        UserActivity ua
        join Posts p on p.OwnerUserId = ua.UserId and p.PostTypeId in (1, 2)
        left join PostLinksInfo pl on pl.PostId = p.Id
    where
        ua.UserRank <= 100
)
select
    utp.UserRank,
    utp.DisplayName,
    utp.PostId,
    utp.Title,
    utp.Score,
    utp.ViewCount,
    utp.Tags,
    utp.CreationDate,
    utp.LinkTypeName,
    utp.LinkCountPerPost,
    (select count(distinct ph.Id)
     from PostHistory ph
     where ph.PostId = utp.PostId
       and ph.PostHistoryTypeId in (4,5,6) -- edits: title, body, tags
       and ph.UserId = utp.UserId) as UserEditsOnPost,
    case when utp.LinkCountPerPost is null then 0 else utp.LinkCountPerPost end +
    coalesce((select count(*) from Comments c where c.PostId = utp.PostId), 0) as TotalEngagement,
    dense_rank() over (order by utp.Score desc, utp.ViewCount desc) as PostPopularityRank,
    (select max(p2.CreationDate)
     from Posts p2
     where p2.ParentId = utp.PostId) as LatestAnswerDate,
    coalesce(utp.Tags, '') || 
    case when utp.LinkTypeName is not null then ' | Links: ' || utp.LinkTypeName else '' end as TagLinkSummary
from
    UserTopPosts utp
where
    utp.rn <= 3
order by
    utp.UserRank,
    PostPopularityRank;