-- {"query": "2947.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1109} 

with RecursiveUserBadgeInfo as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class as BadgeClass,
        count(b.Id) as BadgeCount,
        dense_rank() over (partition by u.Id order by b.Class) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
    group by u.Id, u.DisplayName, u.Reputation, b.Class
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.ParentId,
        p.AcceptedAnswerId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as PostRank
    from Posts p
    inner join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2) and p.Score is not null
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        count(a.Id) filter (where a.PostTypeId = 2) as TotalAnswers,
        avg(a.Score) filter (where a.PostTypeId = 2) as AvgAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAcceptedAnswer
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
UserLastActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(p.LastActivityDate) as LastActivity,
        max(ph.CreationDate) as LastPostHistoryEdit
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostHistoryCloseEvents as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as CloseEventRank
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id::varchar = ph.Comment -- stored as string but matching integer ids
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
),
TopTagsByQuestionCount as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName,
        count(*) as QuestionCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by TagName
    order by QuestionCount desc
    limit 10
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.BadgeClass,
    u.BadgeCount,
    p.Id as PostId,
    p.PostTypeName,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    pas.TotalAnswers,
    pas.AvgAnswerScore,
    pas.HasAcceptedAnswer,
    la.LastActivity,
    la.LastPostHistoryEdit,
    phce.CloseReason,
    phce.CloseDate,
    tg.TagName,
    -- Complicated expression combining string manipulations and null logic
    case
        when p.PostTypeName = 'Question' then
            substr(coalesce(p.OwnerDisplayName, 'anonymous'), 1, 3) || '-' ||
            coalesce(nullif(tg.TagName, ''), 'no-tag') || '-' ||
            case when pas.HasAcceptedAnswer > 0 then 'ACC' else 'NACC' end
        else
            'NA'
    end as CustomLabel,
    -- Window function example: rank posts by score within user
    rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRankForUser
from RecursiveUserBadgeInfo u
inner join RankedPosts p on p.OwnerUserId = u.UserId and p.PostRank <= 3
left join PostAnswerStats pas on pas.QuestionId = p.Id and p.PostTypeId = 1
left join UserLastActivity la on la.UserId = u.UserId
left join PostHistoryCloseEvents phce on phce.PostId = p.Id and phce.CloseEventRank = 1
left join TopTagsByQuestionCount tg on tg.TagName = any(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))
where coalesce(p.Score, 0) > 0 and (phce.CloseDate is null or phce.CloseDate > p.CreationDate)
order by u.Reputation desc, p.Score desc, p.CreationDate desc
limit 100;
