-- {"query": "1248.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1771} 
with RecursiveUserEngagement as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct b.Id) as TotalBadges,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        row_number() over (order by u.Reputation desc, u.Id) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    union all
    select 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.TotalPosts,
        ru.TotalComments,
        ru.TotalBadges,
        ru.QuestionsCount,
        ru.AnswersCount,
        ru.UserRank
    from RecursiveUserEngagement ru
    where ru.UserRank <= 100
), CTE_PostAggregates as (
    select
        p.Id as PostId,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        -- Extract the first tag name, treating Tags as '<tag1><tag2><tag3>'
        trim(both '<>' from split_part(p.Tags, '><', 1)) as PrimaryTag,
        -- Count number of tags extracting with array method
        array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'),1) as TagsCount,
        -- Rank posts by score partitioned by owner ordered descending
        rank() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PostScoreRank,
        -- Difference in days between post creation and owner account creation
        extract(epoch from (p.CreationDate - u.CreationDate))/86400 as DaysSinceUserCreated
    from Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
), CTE_VoteAggregates as (
    select
        v.PostId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotes,
        count(*) filter (where vt.Name = 'DownMod') as DownVotes,
        count(distinct v.UserId) as UniqueVoters,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
), CTE_ClosedQuestions as (
    select ph.PostId, ph.CreationDate as ClosedDate, cr.Name as CloseReason
    from PostHistory ph
    inner join CloseReasonTypes cr on cast(ph.Comment as int) = cr.Id
    where ph.PostHistoryTypeId = 10
), CTE_UserQuestionSummary as (
    select 
        ue.UserId,
        ue.DisplayName,
        count(distinct p.PostId) as ActiveQuestions,
        count(distinct cq.PostId) as ClosedQuestions,
        round(avg(p.Score)::numeric,2) as AvgQuestionScore,
        round(avg(p.ViewCount)::numeric,2) as AvgQuestionViews,
        sum(p.TagsCount) as TotalUserTagsCount
    from RecursiveUserEngagement ue
    left join CTE_PostAggregates p on p.OwnerUserId = ue.UserId and p.PostTypeId = 1
    left join CTE_ClosedQuestions cq on cq.PostId = p.PostId
    group by ue.UserId, ue.DisplayName
), CTE_AnswerAcceptanceRates as (
    select
        p.OwnerUserId as AnswerUserId,
        count(case when q.AcceptedAnswerId = p.Id then 1 end) as AnswersAccepted,
        count(*) as TotalAnswers,
        round(100.0 * count(case when q.AcceptedAnswerId = p.Id then 1 end)/nullif(count(*),0), 2) as AcceptanceRatePercent
    from Posts p
    inner join Posts q on q.Id = p.ParentId and q.PostTypeId = 1
    where p.PostTypeId = 2
    group by p.OwnerUserId
), DistinctUserBadges as (
    select 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        b.TagBased 
    from Badges b
    where b.Date > now() - interval '365 days'
), BadgeSummary as (
    select 
        UserId, 
        count(*) filter (where Class = 1) as GoldBadgesLastYear,
        count(*) filter (where Class = 2) as SilverBadgesLastYear,
        count(*) filter (where Class = 3) as BronzeBadgesLastYear,
        count(distinct BadgeName) as DistinctBadgeTypesLastYear,
        max(TagBased::int) as HasTagBasedBadgeLastYear
    from DistinctUserBadges
    group by UserId
), TopTagsByQuestions as (
    select 
        trim(both '<>' from unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) as Tag,
        count(p.Id) as QuestionsWithTag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    order by QuestionsWithTag desc
    limit 10
)
select
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.QuestionsCount,
    uq.ActiveQuestions,
    uq.ClosedQuestions,
    uq.AvgQuestionScore,
    uq.AvgQuestionViews,
    uq.TotalUserTagsCount,
    aro.AnswersAccepted,
    aro.TotalAnswers,
    aro.AcceptanceRatePercent,
    bs.GoldBadgesLastYear,
    bs.SilverBadgesLastYear,
    bs.BronzeBadgesLastYear,
    bs.DistinctBadgeTypesLastYear,
    bs.HasTagBasedBadgeLastYear,
    tt.Tag as MostUsedTopTag,
    tt.QuestionsWithTag,
    p.PostId as HighestScoringPostId,
    p.PostTypeName as HighestScoringPostType,
    p.Score as HighestPostScore,
    p.ViewCount as HighestPostViewCount,
    p.Title as HighestScoringPostTitle,
    case 
        when cqt.PostId is null then 'No'
        else 'Yes'
    end as HasClosedQuestion,
    pt.Name as LinkTypeMostCommonForUserPosts
from RecursiveUserEngagement ue
inner join CTE_UserQuestionSummary uq on uq.UserId = ue.UserId
left join CTE_AnswerAcceptanceRates aro on aro.AnswerUserId = ue.UserId
left join BadgeSummary bs on bs.UserId = ue.UserId
left join TopTagsByQuestions tt on true
left join LATERAL (
    select p2.Id, pt2.Name, p2.Score, p2.ViewCount, p2.Title
    from Posts p2
    left join PostTypes pt2 on pt2.Id = p2.PostTypeId
    where p2.OwnerUserId = ue.UserId
    order by p2.Score desc nulls last, p2.ViewCount desc nulls last
    limit 1
) p on true
left join CTE_ClosedQuestions cqt on cqt.PostId in (
    select p3.Id from Posts p3 where p3.OwnerUserId = ue.UserId and p3.PostTypeId=1
)
left join (
    select pl.PostId, lt.Name
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId, lt.Name
    order by count(*) desc
    limit 1
) pt on pt.PostId = p.PostId
where ue.UserRank <= 100
order by ue.Reputation desc, ue.UserId
limit 50;