-- {"query": "645.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1196} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count as InitialCount,
        coalesce(p.ViewCount, 0) as TotalViews,
        coalesce(p.Score, 0) as TotalScore
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    union all
    select
        rtc.TagId,
        rtc.TagName,
        rtc.InitialCount,
        rtc.TotalViews + coalesce(p.ViewCount, 0),
        rtc.TotalScore + coalesce(p.Score, 0)
    from RecursiveTagCounts rtc
    join Posts p on p.ParentId = rtc.TagId and p.PostTypeId = 2
    where rtc.TotalViews < 1000000
),
UserBadgeRankings as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        row_number() over (partition by b.UserId order by b.Class, count(*) desc) as rn
    from Badges b
    where b.TagBased = 0
    group by b.UserId, b.Class
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(vt.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes),0) as TotalDownVotes,
        case when u.Views > 0 then round((coalesce(sum(vt.UpVotes),0) * 1.0) / u.Views, 4) else null end as UpVotesPerView
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        coalesce(c.CommentCount, 0) as CommentCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    where p.PostTypeId = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pl.LinkTypeId,
        pt1.Title as PostTitle,
        pt2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts pt1 on pt1.Id = pl.PostId
    join Posts pt2 on pt2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
CloseReasonsCount as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVotesCount
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and crt.Id is not null
    group by ph.PostId, crt.Name
),
UserReputationRanks as (
    select
        Id,
        Reputation,
        dense_rank() over (order by Reputation desc) as ReputationRank
    from Users
)
select
    u.DisplayName,
    u.Reputation,
    u.ReputationRank,
    u.QuestionCount,
    u.AnswerCount,
    u.TotalUpVotes,
    u.TotalDownVotes,
    u.UpVotesPerView,
    ub.Class as BadgeClass,
    ub.BadgeCount,
    tpc.Title as TopQuestionTitle,
    tpc.Score as TopQuestionScore,
    tpc.CommentCount as TopQuestionComments,
    dt.PostTitle as DuplicatePostTitle,
    dt.RelatedPostTitle as DuplicateRelatedTitle,
    cr.CloseReasonName,
    cr.CloseVotesCount,
    rtc.TagName,
    rtc.InitialCount as TagInitialCount,
    rtc.TotalViews as TagTotalViews,
    rtc.TotalScore as TagTotalScore
from UserActivity u
left join UserBadgeRankings ub on ub.UserId = u.UserId and ub.rn = 1
left join TopPostsWithComments tpc on tpc.OwnerUserId = u.UserId and tpc.PostRank = 1
left join DuplicateLinks dt on dt.PostId = tpc.Id
left join CloseReasonsCount cr on cr.PostId = tpc.Id
left join RecursiveTagCounts rtc on rtc.TagName = substring(tpc.Title from '#"([^"]+)"#' for '#')
left join UserReputationRanks urr on urr.Id = u.UserId
where u.Reputation > 1000
order by u.Reputation desc, tpc.Score desc
limit 100;