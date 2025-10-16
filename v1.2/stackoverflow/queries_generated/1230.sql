-- {"query": "1230.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1408} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, null::int as ParentTagId, 1 as Level
    from Tags t
    where t.IsRequired = 1
    union all
    select t.Id, t.TagName, p.Id as ParentTagId, rh.Level + 1
    from Tags t
    join RecursiveTagHierarchy rh on t.Id = rh.ParentTagId
    join Tags p on rh.ParentTagId = p.Id
    where rh.Level < 3
),
UserBadgesSummary as (
    select 
        u.Id UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
TopActiveQuestions as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        case when p.ClosedDate is null then false else true end as IsClosed,
        coalesce(u.DisplayName, p.OwnerDisplayName) OwnerName,
        row_number() over (partition by date_trunc('month', p.CreationDate) order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
      and p.CreationDate >= current_date - interval '1 year'
),
AnswersAndScores as (
    select 
        a.Id AnswerId,
        a.ParentId QuestionId,
        a.CreationDate AnswerCreation,
        a.Score AnswerScore,
        u.DisplayName AnswerOwner,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentsCount,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate) as AnswerRank
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
ClosedQuestionsReasons as (
    select ph.PostId, crt.Name as CloseReason, ph.CreationDate CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
),
RecentHighScoreUsers as (
    select u.Id, u.DisplayName, u.CreationDate, sum(p.Score) TotalScore, count(p.Id) TotalPosts
    from Users u 
    join Posts p on u.Id = p.OwnerUserId
    where u.CreationDate >= current_date - interval '2 years' 
      and p.PostTypeId in (1,2)
    group by u.Id, u.DisplayName, u.CreationDate
    having sum(p.Score) > 500
),
PostsWithVoteStats as (
    select 
        p.Id PostId,
        count(v.Id) filter (where vt.Name = 'UpMod') UpVotes,
        count(v.Id) filter (where vt.Name = 'DownMod') DownVotes,
        count(v.Id) filter (where vt.Name in ('BountyStart','BountyClose')) BountyVotes,
        avg(case when v.BountyAmount is not null then v.BountyAmount end) AvgBountyAmount
    from Posts p
    left join Votes v on p.Id = v.PostId
    left join VoteTypes vt on v.VoteTypeId = vt.Id
    group by p.Id
),
RankedQuestionsWithAnswers as (
    select
        tq.Id QuestionId,
        tq.Title,
        tq.CreationDate,
        tq.Score QuestionScore,
        tq.ViewCount,
        tq.AnswerCount,
        tq.IsClosed,
        tq.OwnerName,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerOwner,
        CloseReason,
        pb.UpVotes,
        pb.DownVotes,
        pb.BountyVotes,
        pb.AvgBountyAmount,
        rank() over (partition by tq.Id order by coalesce(a.AnswerScore, 0) desc) as AnswerRank
    from TopActiveQuestions tq
    left join AnswersAndScores a on tq.Id = a.QuestionId and a.AnswerRank = 1
    left join ClosedQuestionsReasons cqr on cqr.PostId = tq.Id
    left join PostsWithVoteStats pb on pb.PostId = tq.Id
) 
select 
    r.QuestionId,
    left(r.Title, 120) as ShortTitle,
    r.CreationDate,
    r.QuestionScore,
    r.ViewCount,
    r.AnswerCount,
    r.OwnerName,
    r.IsClosed,
    r.CloseReason,
    r.AnswerId,
    r.AnswerScore,
    r.AnswerOwner,
    r.UpVotes,
    r.DownVotes,
    r.BountyVotes,
    coalesce(r.AvgBountyAmount, 0) as AvgBountyAmount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.LastBadgeDate,
    rt.Level as TagHierarchyLevel,
    -- Complex string operation to parse first tag (if any) from Tags. Tags are stored like '<tag1><tag2>'
    coalesce(
       substring(rq.Tags from '<([^>]+)>'),
       'no-tag'
    ) as FirstTag,
    -- Calculate 30 day rolling average of question score over question creation dates
    avg(r.QuestionScore) over (
        order by r.CreationDate 
        range between interval '30 days' preceding and current row
    ) as RollingAvgScore30d,
    -- Conditional complex case with NULL logic
    case 
        when r.IsClosed = true then 'Closed: ' || coalesce(r.CloseReason, 'Unknown')
        when r.QuestionScore > 100 then 'Hot Question'
        when r.AnswerScore is null then 'Unanswered'
        else 'Open'
    end as QuestionStatus
from RankedQuestionsWithAnswers r
left join Users u on u.DisplayName = r.OwnerName
left join UserBadgesSummary ubs on u.Id = ubs.UserId
left join RecursiveTagHierarchy rt on rt.TagName = substring(rq.Tags from '<([^>]+)>')
order by r.QuestionScore desc, r.ViewCount desc
limit 50;