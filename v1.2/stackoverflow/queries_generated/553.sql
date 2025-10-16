-- {"query": "553.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1367} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        row_number() over (order by t.Count desc, t.TagName) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostVotesAgg as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 5) as FavoriteVotes,
        sum(coalesce(v.BountyAmount, 0)) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(a.MaxScore, 0) as MaxAnswerScore,
        coalesce(a.AvgScore, 0) as AvgAnswerScore,
        coalesce(a.TopAnswerId, null) as TopAnswerId
    from Posts q
    left join (
        select
            p.ParentId,
            count(p.Id) as AnswerCount,
            max(p.Score) as MaxScore,
            avg(p.Score) as AvgScore,
            max(p.Id) filter (where p.Score = (select max(score) from Posts where ParentId = p.ParentId)) as TopAnswerId
        from Posts p
        where p.PostTypeId = 2
        group by p.ParentId
    ) a on a.ParentId = q.Id
    where q.PostTypeId = 1
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        rank() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
CloseReasonSummary as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount,
        max(ph.CreationDate) as LastCloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment ~ '^\d+$'
    group by ph.PostId, crt.Name
)
select
    pqs.QuestionId,
    pqs.Title,
    pqs.CreationDate,
    pqs.ViewCount,
    pqs.AnswerCount,
    pqs.MaxAnswerScore,
    pqs.AvgAnswerScore,
    ubs.DisplayName as QuestionOwner,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    pva.UpVotes as QuestionUpVotes,
    pva.DownVotes as QuestionDownVotes,
    pva.FavoriteVotes,
    pva.TotalBounty,
    coalesce(crs.CloseReason, 'Open') as CloseStatus,
    coalesce(crs.CloseCount, 0) as CloseVotesCount,
    coalesce(crs.LastCloseDate, null) as LastCloseDate,
    dt.PostTitle as DuplicateOfTitle,
    rtc.TagName,
    rtc.Count as TagUsageCount,
    ua.PostsLast30Days,
    ua.RecentPostRank,
    concat_ws(' | ',
        case when pqs.AvgAnswerScore > 5 then 'High Avg Answer Score' else 'Avg Answer Score Normal' end,
        case when pqs.ViewCount > 1000 then 'Popular Question' else 'Less Popular' end,
        case when pva.TotalBounty > 0 then concat('Bountied: ', pva.TotalBounty) else 'No Bounty' end
    ) as PerformanceLabel
from PostAnswerStats pqs
left join Users ubs on ubs.Id = (select OwnerUserId from Posts where Id = pqs.QuestionId)
left join PostVotesAgg pva on pva.PostId = pqs.QuestionId
left join CloseReasonSummary crs on crs.PostId = pqs.QuestionId
left join DuplicateLinks dt on dt.PostId = pqs.QuestionId
left join RecursiveTagCounts rtc on rtc.TagName = any(string_to_array(substring(pqs.Tags from 2 for char_length(pqs.Tags)-2), '><'))
left join UserActivityWindow ua on ua.UserId = ubs.Id and ua.PostId = pqs.QuestionId
where pqs.AnswerCount > 0
order by pqs.ViewCount desc, pqs.MaxAnswerScore desc, ubs.Reputation desc
limit 100;