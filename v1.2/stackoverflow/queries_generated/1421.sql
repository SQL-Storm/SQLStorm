-- {"query": "1421.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1572} 
with RecursivePosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        1 as Depth,
        cast(p.Title || ' <-' as varchar(4096)) as Lineage
    from Posts p
    where p.ParentId is null and p.PostTypeId = 1

    union all

    select 
        c.Id,
        c.PostTypeId,
        c.ParentId,
        c.AcceptedAnswerId,
        c.Score,
        c.ViewCount,
        c.OwnerUserId,
        c.CreationDate,
        c.Title,
        r.Depth + 1,
        cast(r.Lineage || ' ' || COALESCE(NULLIF(c.Title, ''), '[No Title]') || ' <-' as varchar(4096)) 
    from Posts c
    inner join RecursivePosts r on c.ParentId = r.Id
)
,
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter(where b.Class = 1) as GoldBadgeCount,
        count(b.Id) filter(where b.Class = 2) as SilverBadgeCount,
        count(b.Id) filter(where b.Class = 3) as BronzeBadgeCount,
        sum(b.Class) as BadgeScore,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
)
,
PostVotesSummary as (
    select 
        p.Id as PostId,
        p.OwnerUserId as UserId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBountyStarted,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as TotalBountyClosed
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id, p.OwnerUserId
)
,
PostHistoricalCloseInfo as (
    select 
        ph.PostId,
        min(ph.CreationDate) filter(where ph.PostHistoryTypeId = 10) as FirstClosedDate,
        max(case when ph.PostHistoryTypeId = 10 then crt.Id end) as CloseReasonId,
        count(*) filter(where ph.PostHistoryTypeId = 10) as NumberOfCloseEvents,
        max(ph.CreationDate) filter(where ph.PostHistoryTypeId = 11) as LastReopenDate
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    group by ph.PostId
)
,
WindowedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.ViewCount,
        p.Score,
        ubc.GoldBadgeCount,
        ubc.SilverBadgeCount,
        ubc.BronzeBadgeCount,
        ubc.BadgeScore,
        pvs.UpVotes,
        pvs.DownVotes,
        pvs.TotalBountyStarted,
        pvs.TotalBountyClosed,
        phci.FirstClosedDate,
        phci.CloseReasonId,
        phci.NumberOfCloseEvents,
        phci.LastReopenDate,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc nulls last) as UserTopRank,
        row_number() over (partition by p.PostTypeId order by p.CreationDate desc) as RecentRankOverall
    from Posts p
    left join UserBadgeCounts ubc on p.OwnerUserId = ubc.UserId
    left join PostVotesSummary pvs on p.Id = pvs.PostId
    left join PostHistoricalCloseInfo phci on p.Id = phci.PostId
    where p.PostTypeId in (1,2)
),
TaggedQuestions as (
    select 
        w.Id,
        replace(
            substring(trim('{' from trim('}' from w.Tags)) from '[^&<>]+'),    -- splash of regex to improve string recovery for one tag
            '>', '', 'g') as CleanTagSamples,
        w.ViewCount,
        w.Score,
        w.AnswerCount,
        w.OwnerUserId
    from Posts w
    where w.PostTypeId = 1 and w.Tags is not null
),
CorrelatedAnswerCounts as (
    select
        q.Id as QuestionId,
        (select count(*) from Posts a where a.ParentId = q.Id and a.Score >= 5) as PopularAnswerCount,
        (select count(*) from Posts a where a.ParentId = q.Id and a.Score <= 0) as LowScoreAnswerCount,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 5 and v.UserId is not null) as FaveVotes
    from Posts q
    where q.PostTypeId = 1
)

select 
    wp.Id as PostId,
    wp.PostTypeId,
    coalesce(wp.Title, '[No Title]') as Title,
    wp.Score,
    wp.ViewCount,
    tbq.CleanTagSamples,
    coalesce(cac.PopularAnswerCount,0) as PopularAnswers,
    coalesce(cac.LowScoreAnswerCount,0) as LowScoreAnswers,
    wp.UpVotes,
    wp.DownVotes,
    wp.TotalBountyStarted,
    wp.TotalBountyClosed,
    wp.GoldBadgeCount, wp.SilverBadgeCount, wp.BronzeBadgeCount,
    wp.BadgeScore,
    phn.Name as CloseReasonName,
    coalesce(phci.NumberOfCloseEvents,0) as CloseEventCount,
    case 
      when phci.FirstClosedDate is null then 'Open'
      when phci.LastReopenDate is not null and phci.LastReopenDate > phci.FirstClosedDate then 'Reopened'
      else 'Closed'
    end as CurrentClosedStatus,
    wp.UserTopRank,
    wp.RecentRankOverall
from WindowedPosts wp
left join TaggedQuestions tbq on tbq.Id = wp.Id
left join CorrelatedAnswerCounts cac on cac.QuestionId = wp.Id
left join PostHistoricalCloseInfo phci on phci.PostId = wp.Id
left join CloseReasonTypes phn on phn.Id = phci.CloseReasonId

where 
    (wp.Score + wp.ViewCount / nullif(nullif(length(coalesce(wp.Title,'')),0),0)) > 10
    and (wp.BadgeScore > 0 or wp.UpVotes > 5)
    and (wp.CurrentClosedStatus != 'Closed' or wp.CurrentClosedStatus is null)
    and (
        (wp.PostTypeId = 1 and wp.UserTopRank <= 5)
        or (wp.PostTypeId = 2 and wp.RecentRankOverall <= 20)
    )
order by wp.UserTopRank asc nulls last, wp.Score desc nulls last, wp.ViewCount desc nulls last
limit 100;