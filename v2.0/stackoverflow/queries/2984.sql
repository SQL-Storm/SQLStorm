-- {"query": "2984.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1374}
with recursive RecursiveUserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, b.Class

    union all

    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.Class,
        r.BadgeCount + 1
    from RecursiveUserBadgeCounts r
    where r.BadgeCount < 5
),
UserPostAnswers as (
    select
        p.OwnerUserId,
        count(case when p.PostTypeId = 2 then 1 end) as AnswerCount,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionCount,
        max(p.Score) as MaxPostScore,
        avg(p.Score) as AvgPostScore
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId
),
PostWithAcceptedAndTags as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        p.AnswerCount,
        p.ViewCount,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        case 
          when p.Tags is not null and p.Tags like '%><%' then substring(p.Tags from '%#"<"?#><([^<>]+)')
          when p.Tags is not null then substring(p.Tags from '%#"<"?#([^<>]+)')
          else null
        end as FirstTag
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
RankedAnswers as (
    select 
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
TopAnswers as (
    select 
        r.ParentId,
        r.Id as AnswerId,
        r.Score,
        r.CreationDate
    from RankedAnswers r
    where r.AnswerRank <= 3
),
PostCommentsCounts as (
    select
        p.Id as PostId,
        count(c.Id) as CommentCount,
        sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
        count(c.Id) as TotalComments
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id
),
BadgesPerUserCTE as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationPercentiles AS (
    select
        UserId,
        Reputation,
        Q1,
        Median,
        Q3
    from (
        select
            Id as UserId,
            Reputation,
            ntile(4) over (order by Reputation) as quartile,
            median_by_quartile.med as Median,
            median_by_quartile.q1 as Q1,
            median_by_quartile.q3 as Q3
        from Users
        cross join lateral (
            select
                max(case when pos = floor((cnt+1)*0.25) then val end) over () as q1,
                max(case when pos = floor((cnt+1)*0.5) then val end) over () as med,
                max(case when pos = floor((cnt+1)*0.75) then val end) over () as q3
            from (
                select
                    row_number() over (order by Reputation) as pos,
                    count(*) over () as cnt,
                    Reputation as val
                from Users
            ) t
        ) median_by_quartile
    ) s
)
select 
    pupt.Id as QuestionId,
    pupt.Title as QuestionTitle,
    pupt.OwnerDisplayName,
    pupt.OwnerReputation,
    pupt.AnswerCount as NumberOfAnswers,
    puc.CommentCount,
    puc.PositiveComments,
    tuc.AnswerCount,
    tuc.QuestionCount,
    tuc.MaxPostScore,
    puc.TotalComments,
    string_agg(distinct lt.Name, ', ') filter (where lt.Name is not null) as LinkTypesToDuplicates,
    array_to_string(array_agg(distinct bpt.Name), ', ') as PostHistoryTypesOnQuestion,
    wabc.SmallestClassBadgeCount,
    row_number() over (partition by pupt.Id order by topa.Score desc NULLS LAST, topa.CreationDate asc NULLS LAST) as BestAnswerRank,
    topa.AnswerId as BestAnswerId,
    topa.Score as BestAnswerScore
from PostWithAcceptedAndTags pupt
left join UserPostAnswers tuc on tuc.OwnerUserId = pupt.OwnerUserId
left join PostCommentsCounts puc on puc.PostId = pupt.Id
left join PostLinks pl on pl.PostId = pupt.Id
left join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
left join PostHistory ph on ph.PostId = pupt.Id and ph.PostHistoryTypeId in (10,11,33)
left join PostHistoryTypes bpt on bpt.Id = ph.PostHistoryTypeId
left join (
    select 
        UserId,
        min(BadgeCount) as SmallestClassBadgeCount
    from (
        select 
            UserId,
            Class,
            count(*) as BadgeCount
        from Badges
        group by UserId, Class
    ) bgroup
    group by UserId
) wabc on wabc.UserId = pupt.OwnerUserId
left join TopAnswers topa on topa.ParentId = pupt.Id
where 
    (puc.CommentCount > 0 or tuc.AnswerCount > 5)
    and pupt.OwnerReputation is not null
    and pupt.ViewCount > 100
    and pupt.CreationDate between cast('2024-10-01 12:34:56' as timestamp) - interval '2 years' and cast('2024-10-01 12:34:56' as timestamp)
group by 
    pupt.Id, pupt.Title, pupt.OwnerDisplayName, pupt.OwnerReputation, pupt.AnswerCount, puc.CommentCount, puc.PositiveComments, puc.TotalComments,
    tuc.AnswerCount, tuc.QuestionCount, tuc.MaxPostScore, wabc.SmallestClassBadgeCount, topa.AnswerId, topa.Score, topa.CreationDate, pupt.ViewCount
having
    sum(case when lt.Name = 'Duplicate' then 1 else 0 end) > 0
order by 
    pupt.OwnerReputation desc NULLS LAST,
    pupt.ViewCount desc NULLS LAST,
    BestAnswerScore desc NULLS LAST
limit 100;