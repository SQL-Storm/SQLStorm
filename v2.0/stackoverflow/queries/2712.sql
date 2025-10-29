-- {"query": "2712.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1429}
with RecursiveTagCounts as (
    select t.Id, t.TagName, t.Count,
        row_number() over (order by t.Count desc, t.TagName) as rn
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
), TopTags as (
    select Id, TagName from RecursiveTagCounts where rn <= 50
), RecentActiveUsers as (
    select u.Id, u.DisplayName, u.Reputation, u.CreationDate,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct b.Id) as BadgesEarned
    from Users u
    left join PostHistory ph on ph.UserId = u.Id and ph.CreationDate > (cast('2024-10-01' as date) - interval '90 days')
    left join Votes v on v.UserId = u.Id and v.CreationDate > (cast('2024-10-01' as date) - interval '90 days')
    left join Badges b on b.UserId = u.Id and b.Date > (cast('2024-10-01' as date) - interval '90 days')
    where u.LastAccessDate > (cast('2024-10-01' as date) - interval '30 days') and u.Reputation > 1000
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
), MostActiveQuestions as (
    select p.Id, p.Title, p.Tags, p.CreationDate, p.OwnerUserId,
        p.ViewCount, p.Score, p.AnswerCount,
        rank() over (partition by p.OwnerUserId order by p.ViewCount desc) as QuestionRank
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate > (cast('2024-10-01' as date) - interval '180 days')
), FeaturedQuestionsWithLinks as (
    select mq.Id as QuestionId, mq.Title, mq.OwnerUserId, mq.ViewCount, mq.Score, mq.AnswerCount,
        string_agg(distinct (lt.Name || ':' || cast(pl.RelatedPostId as varchar)), ', ') filter (where lt.Name is not null) as LinkDetails
    from MostActiveQuestions mq
    left join PostLinks pl on pl.PostId = mq.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where mq.QuestionRank <= 3
    group by mq.Id, mq.Title, mq.OwnerUserId, mq.ViewCount, mq.Score, mq.AnswerCount
), UserBadgeSummary as (
    select u.Id as UserId, u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
), UserQuestionAnswerStats as (
    select u.Id as UserId,
        count(distinct q.Id) as QuestionsCount,
        count(distinct a.Id) as AnswersCount,
        coalesce(avg(q.Score),0) as AvgQuestionScore,
        coalesce(avg(a.Score),0) as AvgAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswersCount
    from Users u
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    where u.Reputation > 500
    group by u.Id
), UserActivityRank as (
    select u.Id as UserId,
           dense_rank() over (order by ua.AnswersCount desc, ua.QuestionsCount desc, u.Reputation desc) as ActivityRank
    from Users u
    join UserQuestionAnswerStats ua on ua.UserId = u.Id
    where u.Reputation > 500
), CombinedUserStats as (
    select u.Id, u.DisplayName, u.Reputation, ua.QuestionsCount, ua.AnswersCount, ua.AcceptedAnswersCount,
           ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ua.AvgQuestionScore, ua.AvgAnswerScore, ar.ActivityRank
    from Users u
    join UserQuestionAnswerStats ua on ua.UserId = u.Id
    join UserBadgeSummary ubs on ubs.UserId = u.Id
    join UserActivityRank ar on ar.UserId = u.Id
    where u.Reputation > 1000
), FavTagsPerUser as (
    select p.OwnerUserId, tt.TagName
    from Posts p
    cross join lateral (
        select unnest(string_to_array(substring(p.Tags from 2 for (char_length(p.Tags)-2)), '><')) as TagName
    ) as tt
    join TopTags t on t.TagName = tt.TagName
    where p.PostTypeId = 1
)
select
    cu.Id as UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.QuestionsCount,
    cu.AnswersCount,
    cu.AcceptedAnswersCount,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.AvgQuestionScore,
    cu.AvgAnswerScore,
    cu.ActivityRank,
    ra.EditsMade,
    ra.UpVotesGiven,
    ra.BadgesEarned,
    array_to_string(array_agg(distinct FavTagsPerUser.TagName), ', ') as FavoriteTags,
    fq.LinkDetails as TopQuestionLinks,
    concat_ws(' / ', fq.Title,
              'Score:', cast(fq.Score as varchar),
              'Views:', cast(fq.ViewCount as varchar)) as HighlightedQuestionSummary
from CombinedUserStats cu
left join RecentActiveUsers ra on ra.Id = cu.Id
left join FeaturedQuestionsWithLinks fq on fq.OwnerUserId = cu.Id
left join FavTagsPerUser on FavTagsPerUser.OwnerUserId = cu.Id
group by cu.Id, cu.DisplayName, cu.Reputation, cu.QuestionsCount, cu.AnswersCount, cu.AcceptedAnswersCount,
         cu.GoldBadges, cu.SilverBadges, cu.BronzeBadges, cu.AvgQuestionScore, cu.AvgAnswerScore, cu.ActivityRank,
         ra.EditsMade, ra.UpVotesGiven, ra.BadgesEarned, fq.LinkDetails, fq.Title, fq.Score, fq.ViewCount
having (cu.QuestionsCount + cu.AnswersCount) > 10
order by cu.ActivityRank, cu.Reputation desc
limit 100;