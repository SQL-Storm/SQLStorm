-- {"query": "2746.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1215} 
with RecursiveTagStats as (
    select 
        t.Id as TagId,
        t.TagName,
        t.Count as TagUsageCount,
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Score as QuestionScore,
        p.ViewCount,
        p.CreationDate
    from Tags t
    join Posts p on p.PostTypeId = 1 and POSITION(CONCAT('<', t.TagName, '>') IN COALESCE(p.Tags, '')) > 0
    where t.Count > 1000
), UserAnswerStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(pa.Id) as AnswerCount,
        avg(pa.Score) as AvgAnswerScore,
        max(pa.CreationDate) as LastAnswerDate
    from Users u
    left join Posts pa on pa.PostTypeId = 2 and pa.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
), QuestionWithAcceptedAnswerInfo as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.CreationDate as QuestionCreationDate,
        a.Id as AcceptedAnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    where q.PostTypeId = 1
), RankedQuestions as (
    select
        q.*,
        row_number() over (partition by extract(year from q.QuestionCreationDate) order by q.Score desc) as YearlyRank,
        rank() over (order by q.ViewCount desc) as ViewRank
    from QuestionWithAcceptedAnswerInfo q
), CloseReasonsCount as (
    select 
        ch.ClosedDate::date as CloseDate,
        crt.Name as CloseReason,
        count(*) as ClosedPostsCount
    from Posts ch
    join PostHistory ph on ph.PostId = ch.Id and ph.PostHistoryTypeId = 10
    join CloseReasonTypes crt on crt.Id = CAST(ph.Comment AS int)
    where ch.ClosedDate is not null
    group by ch.ClosedDate::date, crt.Name
), UsersWithGoldBadgesAndHighReputation as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadgeCount,
        count(b.Id) filter (where b.Class = 2) as SilverBadgeCount,
        count(b.Id) filter (where b.Class = 3) as BronzeBadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having u.Reputation > 10000 and count(b.Id) filter (where b.Class = 1) > 0
)
select distinct
    rq.QuestionId,
    rq.Title,
    rq.QuestionScore,
    rq.ViewCount,
    u.DisplayName as QuestionOwner,
    uas.AnswerCount,
    uas.AvgAnswerScore,
    cr.ClosedPostsCount,
    cr.CloseReason,
    uts.TagName,
    uts.TagUsageCount,
    ugh.GoldBadgeCount,
    ugh.SilverBadgeCount,
    ugh.BronzeBadgeCount,
    concat_ws(' :: ', 
        left(rq.Title, 30), 
        coalesce(uts.TagName, 'NoTag'), 
        cast(rq.QuestionScore as varchar), 
        cast(rq.ViewCount as varchar)) as CompositeInfo,
    case 
        when rq.ViewCount > 100000 then 'Hot'
        when rq.ViewCount between 10000 and 100000 then 'Warm'
        else 'Cold'
    end as QuestionPopularityCategory,
    (select count(*) 
     from Comments c
     where c.PostId = rq.QuestionId and c.CreationDate > rq.QuestionCreationDate) as CommentCountSinceCreation
from RankedQuestions rq
left join Users u on u.Id = rq.OwnerUserId
left join UserAnswerStats uas on uas.UserId = rq.OwnerUserId
left join CloseReasonsCount cr on cr.CloseDate = rq.QuestionCreationDate::date
left join RecursiveTagStats uts on uts.QuestionId = rq.QuestionId
left join UsersWithGoldBadgesAndHighReputation ugh on ugh.Id = rq.OwnerUserId
where rq.YearlyRank <= 10
  and coalesce(ugh.GoldBadgeCount,0) >= 1
  and (uas.AvgAnswerScore is null or uas.AvgAnswerScore > 2)
union
select 
    p.Id as QuestionId,
    p.Title,
    p.Score as QuestionScore,
    p.ViewCount,
    u.DisplayName as QuestionOwner,
    0 as AnswerCount,
    null as AvgAnswerScore,
    0 as ClosedPostsCount,
    null as CloseReason,
    null as TagName,
    0 as TagUsageCount,
    0 as GoldBadgeCount,
    0 as SilverBadgeCount,
    0 as BronzeBadgeCount,
    left(p.Title, 30) as CompositeInfo,
    'Cold' as QuestionPopularityCategory,
    0 as CommentCountSinceCreation
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
  and p.AcceptedAnswerId is null
  and p.Score < 0
  and not exists (
      select 1 from Comments c where c.PostId = p.Id
  )
order by ViewCount desc, QuestionScore desc
limit 100;