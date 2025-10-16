-- {"query": "349.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1378} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.Reputation,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.Tags like '%' || t.TagName || '%'
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
TopRecentPosts as (
    select
        Id,
        TagName,
        Count,
        PostId,
        CreationDate,
        Score,
        ViewCount,
        OwnerUserId,
        Reputation
    from RecursiveTagCounts
    where rn <= 5
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostVoteStats as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        count(v.Id) as TotalVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as QuestionsLast30Days,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as AnswersLast30Days,
        sum(coalesce(p.Score,0)) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as ScoreLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.CreationDate < now() - interval '30 days'
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
CorrelatedComments as (
    select
        p.Id as PostId,
        (select count(*) from Comments c where c.PostId = p.Id and c.CreationDate > p.CreationDate) as CommentsAfterPostCreation
    from Posts p
    where p.PostTypeId = 1
)
select
    tr.TagName,
    tr.Count as TagUsageCount,
    tr.PostId,
    tr.CreationDate as PostCreationDate,
    tr.Score as PostScore,
    tr.ViewCount as PostViews,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    coalesce(pvs.UpVotes,0) as PostUpVotes,
    coalesce(pvs.DownVotes,0) as PostDownVotes,
    coalesce(pas.AnswerCount,0) as NumberOfAnswers,
    coalesce(pas.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(pas.AvgAnswerScore,0) as AvgAnswerScore,
    pcr.CloseReason,
    pcr.CloseDate,
    uaw.QuestionsLast30Days,
    uaw.AnswersLast30Days,
    uaw.ScoreLast30Days,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.RelatedPostTitle as DuplicateOfPostTitle,
    cc.CommentsAfterPostCreation,
    case
        when tr.Score > 100 then 'Hot'
        when tr.Score between 50 and 100 then 'Warm'
        else 'Cold'
    end as PostHeat,
    length(coalesce(p.Body,'')) as BodyLength,
    strpos(lower(coalesce(p.Title,'')), 'sql') > 0 as TitleContainsSQL,
    case when p.ClosedDate is null then 0 else 1 end as IsClosed
from TopRecentPosts tr
left join Users u on u.Id = tr.OwnerUserId
left join UserBadgeCounts ub on ub.UserId = tr.OwnerUserId
left join PostVoteStats pvs on pvs.PostId = tr.PostId
left join PostAnswerStats pas on pas.QuestionId = tr.PostId
left join PostCloseReasons pcr on pcr.PostId = tr.PostId
left join UserActivityWindow uaw on uaw.UserId = tr.OwnerUserId
left join DuplicateLinks dl on dl.PostId = tr.PostId
left join CorrelatedComments cc on cc.PostId = tr.PostId
left join Posts p on p.Id = tr.PostId
where tr.TagName in (
    select TagName from Tags where Count > 1000
)
order by tr.Count desc, tr.Score desc
limit 100;