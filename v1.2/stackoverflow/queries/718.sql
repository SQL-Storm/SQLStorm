-- {"query": "718.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1118} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
UserBadgeSummary as (
    select
        UserId,
        DisplayName,
        count(case when BadgeClass = 1 then 1 end) as GoldBadges,
        count(case when BadgeClass = 2 then 1 end) as SilverBadges,
        count(case when BadgeClass = 3 then 1 end) as BronzeBadges,
        max(BadgeName) filter (where BadgeRank = 1) as MostRecentBadge
    from RecursiveUserBadges
    group by UserId, DisplayName
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.OwnerUserId,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Score > 10 then 1 else 0 end) as HighScoreAnswers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.CreationDate >= (cast('2024-10-01' as date) - interval '1 year')
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId
),
TopTags as (
    select 
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
        count(*) as TagCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    having count(*) > 1000
),
PostLinkStats as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as LinkedPostsCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateLinksCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
UserActivityRank as (
    select 
        u.Id as UserId,
        u.DisplayName,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        dense_rank() over (order by sum(case when p.PostTypeId = 2 then 1 else 0 end) desc) as AnswerRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
)
select 
    uas.UserId,
    uas.DisplayName,
    uas.QuestionCount,
    uas.AnswerCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.MostRecentBadge,
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.AnswerCount as QuestionAnswerCount,
    qas.MaxAnswerScore,
    qas.AvgAnswerScore,
    qas.HighScoreAnswers,
    pls.LinkedPostsCount,
    pls.DuplicateLinksCount,
    tt.Tag as PopularTag,
    tt.TagCount,
    row_number() over (partition by uas.UserId order by qas.AnswerCount desc nulls last) as UserTopQuestionRank
from UserActivityRank uas
left join UserBadgeSummary ubs on uas.UserId = ubs.UserId
left join QuestionAnswerStats qas on qas.OwnerUserId = uas.UserId
left join PostLinkStats pls on pls.PostId = qas.QuestionId
left join TopTags tt on tt.Tag in (
    select unnest(string_to_array(substring(qas.Title from 2 for length(qas.Title)-2), '><'))
)
where uas.AnswerRank <= 100
and (qas.AnswerCount > 0 or pls.LinkedPostsCount > 0)
union
select 
    u.Id as UserId,
    u.DisplayName,
    0 as QuestionCount,
    0 as AnswerCount,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    null as MostRecentBadge,
    null as QuestionId,
    null as QuestionTitle,
    0 as QuestionAnswerCount,
    null as MaxAnswerScore,
    null as AvgAnswerScore,
    0 as HighScoreAnswers,
    0 as LinkedPostsCount,
    0 as DuplicateLinksCount,
    null as PopularTag,
    0 as TagCount,
    0 as UserTopQuestionRank
from Users u
where not exists (
    select 1 from Posts p where p.OwnerUserId = u.Id
)
order by AnswerCount desc nulls last, GoldBadges desc nulls last, UserTopQuestionRank asc nulls last
limit 200;