-- {"query": "2775.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1531} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date is not null
),
UserTopBadges as (
    select UserId, BadgeName, Class, Date from RecursiveUserBadges where BadgeRank <= 3
),
QuestionAnswerStats as (
    select
        p.OwnerUserId,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersCount,
        coalesce(sum(case when p.PostTypeId = 1 then p.Score else 0 end),0) as TotalQuestionScore,
        coalesce(sum(case when p.PostTypeId = 2 then p.Score else 0 end),0) as TotalAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId
),
UserVoteSummary as (
    select
        p.OwnerUserId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        count(distinct v.Id) as TotalVotesReceived
    from Posts p
    left join Votes v on p.Id = v.PostId
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId
),
UserCommentActivity as (
    select
        c.UserId,
        count(distinct c.Id) as CommentsMade,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.CreationDate > now() - interval '30 days' then 1 else 0 end) as CommentsLast30Days
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
TopLinkedPosts as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as LinkedCount,
        max(pl.CreationDate) as LastLinkDate
    from PostLinks pl
    group by pl.PostId
    having count(distinct pl.RelatedPostId) > 5
),
UserPopularQuestions as (
    select
        p.OwnerUserId,
        p.Id as QuestionId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Title,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PopularRank
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null and p.OwnerUserId <> -1
),
FinalUserSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        case when u.Location is null or trim(u.Location) = '' then 'Unknown' else u.Location end as LocationNormalized,
        coalesce(qa.QuestionsCount,0) as Questions,
        coalesce(qa.AnswersCount,0) as Answers,
        coalesce(vs.UpVotesReceived,0) as UpVotesReceived,
        coalesce(vs.DownVotesReceived,0) as DownVotesReceived,
        coalesce(ca.CommentsMade,0) as CommentsMade,
        ca.CommentsLast30Days,
        tb.BadgeName,
        tb.Class as BadgeClass,
        tp.QuestionId as TopQuestionId,
        tp.Title as TopQuestionTitle,
        tp.Score as TopQuestionScore,
        tp.ViewCount as TopQuestionViewCount,
        round(avg(case when p.PostTypeId in (1,2) then p.Score else null end) over (partition by u.Id),2) as AvgPostScore,
        max(case when p.PostTypeId = 1 then p.Score else null end) as MaxQuestionScore,
        max(case when p.PostTypeId = 2 then p.Score else null end) as MaxAnswerScore,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 1) as GoldBadgesCount,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 2) as SilverBadgesCount,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 3) as BronzeBadgesCount
    from Users u
    left join QuestionAnswerStats qa on u.Id = qa.OwnerUserId
    left join UserVoteSummary vs on u.Id = vs.OwnerUserId
    left join UserCommentActivity ca on u.Id = ca.UserId
    left join UserTopBadges tb on u.Id = tb.UserId and tb.BadgeRank = 1
    left join UserPopularQuestions tp on u.Id = tp.OwnerUserId and tp.PopularRank = 1
    left join Posts p on u.Id = p.OwnerUserId
    where u.Id in (
        select distinct OwnerUserId from Posts where OwnerUserId is not null and OwnerUserId <> -1
    )
)
select
    fus.UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.LocationNormalized,
    fus.Questions,
    fus.Answers,
    fus.UpVotesReceived,
    fus.DownVotesReceived,
    fus.CommentsMade,
    fus.CommentsLast30Days,
    fus.BadgeName as TopBadge,
    fus.BadgeClass,
    fus.GoldBadgesCount,
    fus.SilverBadgesCount,
    fus.BronzeBadgesCount,
    fus.TopQuestionId,
    fus.TopQuestionTitle,
    fus.TopQuestionScore,
    fus.TopQuestionViewCount,
    fus.AvgPostScore,
    fus.MaxQuestionScore,
    fus.MaxAnswerScore,
    case
        when fus.Reputation > 10000 then 'Legendary'
        when fus.Reputation between 5000 and 9999 then 'Experienced'
        when fus.Reputation between 1000 and 4999 then 'Intermediate'
        else 'Beginner'
    end as ReputationCategory,
    sign(fus.Answers - fus.Questions) as AnswerQuestionBias,
    length(coalesce(fus.TopQuestionTitle, '')) -
        length(replace(coalesce(fus.TopQuestionTitle, ''), ' ', '')) as TopQuestionTitleWordCount
from FinalUserSummary fus
where fus.Questions + fus.Answers > 10
order by fus.Reputation desc, fus.GoldBadgesCount desc, fus.Answers desc
limit 100;