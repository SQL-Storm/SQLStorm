-- {"query": "2486.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1541}
with RecursiveTagCounts as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        abs(length(t.TagName) - length(replace(t.TagName, 'a', ''))) as a_count,
        row_number() over (order by t.Count desc) as rn
    from Tags t
    where t.TagName is not null
),
FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(p.Title, '') as Title,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.ClosedDate,
        p.LastActivityDate
    from Posts p
    where p.PostTypeId in (1, 2) and p.Score > 5
),
AnswerAggregates as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerTotal,
        max(p.Score) as MaxAnswerScore,
        avg(p.Score) as AvgAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRanks as (
    select
        u.Id as UserId,
        u.Reputation,
        rank() over (order by u.Reputation desc) as RepRank
    from Users u
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserActiveDayStats as (
    select
        u.Id as UserId,
        date_trunc('day', u.CreationDate) as CreationDay,
        date_trunc('day', u.LastAccessDate) as LastAccessDay,
        extract(epoch from (u.LastAccessDate - u.CreationDate))/86400 as ActiveDays
    from Users u
),
PostLinkCounts as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as RelatedPostCount,
        count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicateLinkCount
    from PostLinks pl
    group by pl.PostId
),
QuestionWithStats as (
    select
        fp.Id,
        fp.Title,
        fp.Score,
        fp.ViewCount,
        fp.Tags,
        coalesce(aa.AnswerTotal, 0) as AnswerCount,
        coalesce(aa.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(aa.AvgAnswerScore, 0) as AvgAnswerScore,
        plc.RelatedPostCount,
        plp.DuplicateLinkCount,
        phc.CloseReasonName,
        fp.ClosedDate,
        fp.PostTypeId,
        fp.CreationDate
    from FilteredPosts fp
    left join AnswerAggregates aa on aa.QuestionId = fp.Id
    left join PostLinkCounts plc on plc.PostId = fp.Id
    left join PostLinkCounts plp on plp.PostId = fp.Id and plp.DuplicateLinkCount > 0
    left join PostCloseReasons phc on phc.PostId = fp.Id
    where fp.PostTypeId = 1
),
RankedQuestions as (
    select
        qws.Id,
        qws.Title,
        qws.Score,
        qws.ViewCount,
        qws.Tags,
        qws.AnswerCount,
        qws.MaxAnswerScore,
        qws.AvgAnswerScore,
        qws.RelatedPostCount,
        qws.DuplicateLinkCount,
        qws.CloseReasonName,
        qws.ClosedDate,
        qws.PostTypeId,
        qws.CreationDate,
        row_number() over (
            partition by case when qws.CloseReasonName is null then 'Open' else 'Closed' end
            order by qws.Score desc, qws.ViewCount desc) as rn
    from QuestionWithStats qws
),
ComplexRanking as (
    select
        rq.Id,
        rq.Title,
        rq.Score,
        rq.ViewCount,
        rq.Tags,
        rq.AnswerCount,
        rq.MaxAnswerScore,
        rq.AvgAnswerScore,
        rq.RelatedPostCount,
        rq.DuplicateLinkCount,
        rq.CloseReasonName,
        rq.ClosedDate,
        rq.PostTypeId,
        rq.Title as TitleForCalc,
        rq.CreationDate,
        rq.Id as OwnerUserId,
        rq.rn
    from RankedQuestions rq
    where rq.rn <= 100
),
ComputedComplexity as (
    select
        cr.Id,
        cr.Title,
        cr.Score,
        cr.ViewCount,
        cr.Tags,
        cr.AnswerCount,
        cr.MaxAnswerScore,
        cr.AvgAnswerScore,
        cr.RelatedPostCount,
        cr.DuplicateLinkCount,
        cr.CloseReasonName,
        cr.ClosedDate,
        cr.OwnerUserId,
        -- Calculate title complexity: number of vowels * length of title modulo 7 plus score normalized
        (
            (
             (length(lower(cr.TitleForCalc)) - length(replace(lower(cr.TitleForCalc), 'a', ''))) +
             (length(lower(cr.TitleForCalc)) - length(replace(lower(cr.TitleForCalc), 'e', ''))) +
             (length(lower(cr.TitleForCalc)) - length(replace(lower(cr.TitleForCalc), 'i', ''))) +
             (length(lower(cr.TitleForCalc)) - length(replace(lower(cr.TitleForCalc), 'o', ''))) +
             (length(lower(cr.TitleForCalc)) - length(replace(lower(cr.TitleForCalc), 'u', '')))
            ) * length(cr.TitleForCalc) % 7
        ) + (cr.Score / nullif(cr.AnswerCount, 0) + 1) as TitleComplexityScore,
        cr.CreationDate
    from ComplexRanking cr
)
select
    cc.Id as QuestionId,
    cc.Title,
    cc.Score,
    cc.ViewCount,
    cc.AnswerCount,
    cc.MaxAnswerScore,
    round(cast(cc.AvgAnswerScore as numeric), 2) as AvgAnswerScore,
    cc.RelatedPostCount,
    cc.DuplicateLinkCount,
    coalesce(cc.CloseReasonName, 'Open') as Status,
    cc.ClosedDate,
    cc.TitleComplexityScore,
    (
      select a.Id
      from Posts a
      where a.ParentId = cc.Id and a.PostTypeId = 2
      order by a.Score desc nulls last, a.CreationDate asc
      fetch first 1 row only
    ) as TopAnswerId,
    case 
      when exists (select 1 from Posts p2 where p2.Id = cc.Id) then
        case 
          when exists (
              select 1
              from PostHistory phh
              where phh.PostId = cc.Id 
                and phh.CreationDate > (
                    select p3.CreationDate from Posts p3 where p3.Id = (
                        select p2.AcceptedAnswerId from Posts p2 where p2.Id = cc.Id
                    )
                )
                and phh.PostHistoryTypeId in (4,5,6)
          ) then true
          else false
        end
      else null
    end as EditedAfterAcceptedAnswer,
    coalesce((select sum(bc.BadgeCount) from UserBadgeRanks bc where bc.UserId = cc.OwnerUserId), 0) as OwnerBadgeCount,
    u.Reputation as OwnerReputation,
    greatest(0, extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - cc.CreationDate))/86400 * (cc.Score + coalesce(cc.ViewCount,0) * 0.01)) as WeightedAgeScore
from ComputedComplexity cc
left join Users u on u.Id = cc.OwnerUserId
order by cc.TitleComplexityScore desc, cc.Score desc
limit 50;