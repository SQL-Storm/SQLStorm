-- {"query": "2747.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1051} 
with RecursiveUserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(b.Id) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id and b.Date <= now() - interval '1 year'
    group by u.Id, u.DisplayName, b.Class

    union all

    select
        r.UserId,
        r.DisplayName,
        case when r.Class is null then 0 else r.Class + 1 end as Class,
        r.BadgeCount
    from RecursiveUserBadgeSummary r
    where r.Class < 3 and r.Class is not null
),
UserPostStats as (
    select
        u.Id as UserId,
        count(p.Id) filter(where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter(where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalScore,
        max(p.CreationDate) as LastPostDate,
        avg(p.ViewCount) filter(where p.PostTypeId = 1 and p.ViewCount is not null) as AvgQuestionViews,
        string_agg(distinct substring(p.Tags from '<([^>]+)>'), ',' order by substring(p.Tags from '<([^>]+)>')) as TagList
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
LatestClosedQuestions as (
    select
        ph.PostId,
        ph.Comment::int as CloseReasonId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = ph.Comment::int
    where ph.PostHistoryTypeId = 10
),
QuestionAnswerWindow as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        p.CreationDate,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank,
        count(*) over (partition by p.ParentId) as TotalAnswers
    from Posts p
    where p.PostTypeId = 2
),
UserLastActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        greatest(u.LastAccessDate, coalesce(max(p.LastActivityDate), timestamp '1900-01-01')) as LastActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.LastAccessDate
)
select distinct
    u.DisplayName,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalScore,
    ups.AvgQuestionViews,
    case 
        when rbs.Class = 1 then 'Gold'
        when rbs.Class = 2 then 'Silver'
        when rbs.Class = 3 then 'Bronze'
        else 'None'
    end as BadgeClass,
    coalesce(lcq.CloseReason, 'Not Closed') as LastCloseReason,
    lcq.CloseDate,
    qa.AnswerRank,
    qa.TotalAnswers,
    qa.Score as TopAnswerScore,
    ulast.LastActivity,
    -- complex string expression: concatenate tags uppercase and reverse order
    string_agg(upper(trim(tg.trimmed_tag)), ',' order by tg.trimmed_tag desc) as UpperTagsReverse
from Users u
left join UserPostStats ups on ups.UserId = u.Id
left join RecursiveUserBadgeSummary rbs on rbs.UserId = u.Id
left join LatestClosedQuestions lcq on lcq.PostId = (select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by p.CreationDate desc limit 1)
left join QuestionAnswerWindow qa on qa.QuestionId = (select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by p.CreationDate desc limit 1) and qa.AnswerRank = 1
left join UserLastActivity ulast on ulast.UserId = u.Id
left join lateral (
    select trim(tag) as trimmed_tag
    from unnest(string_to_array(coalesce(ups.TagList,''), ',')) as tag
    where tag is not null and tag <> ''
) tg on true
where 
    -- complex predicate with null logic and calculations:
    (ups.QuestionCount > 10 or ups.AnswerCount > 20)
    and (ups.TotalScore is not null and ups.TotalScore > 100)
    and (rbs.Class is not null or ups.AvgQuestionViews > 500)
    and (
        lcq.CloseDate is null 
        or lcq.CloseDate > now() - interval '6 months'
        or qa.AnswerRank = 1
    )
order by ups.TotalScore desc, ulast.LastActivity desc
limit 50;