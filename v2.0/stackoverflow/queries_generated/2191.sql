-- {"query": "2191.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1908} 
with RecursiveUserPosts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        row_number() over(partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2) -- Questions and Answers
),
RecursiveAnswersCTE as (
    select 
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.CreationDate as AnswerCreationDate,
        p.Score as AnswerScore,
        p.OwnerUserId as AnswerOwner,
        p.Body as AnswerBody,
        row_number() over (partition by p.ParentId order by p.CreationDate) as AnswerOrder
    from Posts p
    where p.PostTypeId = 2 and p.ParentId is not null
),
UserBadgeStats as (
    select 
        b.UserId,
        max(case when b.Class = 1 then 1 else 0 end) as HasGoldBadge,
        max(case when b.Class = 2 then 1 else 0 end) as HasSilverBadge,
        max(case when b.Class = 3 then 1 else 0 end) as HasBronzeBadge,
        count(*) as TotalBadges,
        count(distinct b.Name) as DistinctBadgeNames,
        min(b.Date) as FirstBadgeDate,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
TopTags as (
    select 
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        count(*) as TagCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    order by TagCount desc
    limit 50
),
UserTopTags as (
    select 
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as UserTag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null and p.OwnerUserId is not null
),
UserTagIntersection as (
    select distinct ut.UserId, tt.Tag
    from UserTopTags ut
    inner join TopTags tt on ut.UserTag = tt.Tag
),
TagQuestions as (
    select 
        p.Id as QuestionId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagTopQuestionRanks as (
    select
        tq.*,
        rank() over(partition by tq.Tag order by tq.Score desc, tq.ViewCount desc, tq.CreationDate desc) as RankInTag
    from TagQuestions tq
),
-- Get the most active users who have posted top ranked questions on popular tags
ActiveUsersTopQuestions as (
    select 
        rup.UserId,
        rup.DisplayName,
        count(distinct ttr.QuestionId) as TopRankedQuestionsCount,
        count(distinct rup.PostId) as TotalPosts,
        max(rup.PostCreationDate) as LastPostDate,
        max(ub.TotalBadges) as TotalBadges,
        max(ub.HasGoldBadge) as HasGold,
        max(ub.HasSilverBadge) as HasSilver,
        max(ub.HasBronzeBadge) as HasBronze
    from RecursiveUserPosts rup
    left join TagTopQuestionRanks ttr on ttr.QuestionId = rup.PostId and ttr.RankInTag <= 10
    left join UserBadgeStats ub on ub.UserId = rup.UserId
    where ttr.QuestionId is not null
    group by rup.UserId, rup.DisplayName
),
-- Determine the duplicate questions linked to top ranked questions
QuestionDuplicates as (
    select 
        pl.PostId as OriginalQuestionId,
        pl.RelatedPostId as DuplicateQuestionId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    inner join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3 -- Duplicate
),
-- Aggregate votes on posts with complicated logic including NULL
PostVoteStats as (
    select 
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty,
        count(distinct v.UserId) as DistinctVoters,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    group by v.PostId
),
-- Compile windowed ranking per user of their answers scores, using correlated subquery filtering recent answers
UserAnswerRanks as (
    select 
        a.AnswerOwner as UserId,
        a.AnswerId,
        a.QuestionId,
        a.AnswerScore,
        a.AnswerCreationDate,
        row_number() over(partition by a.AnswerOwner order by a.AnswerScore desc, a.AnswerCreationDate desc) as AnswerRank,
        (select count(*) from Posts p where p.PostTypeId=2 and p.OwnerUserId=a.AnswerOwner and p.CreationDate >= now() - interval '1 year') as RecentAnswersCount
    from RecursiveAnswersCTE a
),
-- Find users who have high ranked answers with at least 5 recent answers
HighRankedAnswerUsers as (
    select distinct 
        uar.UserId
    from UserAnswerRanks uar
    where uar.AnswerRank <= 5 and uar.RecentAnswersCount >= 5
),
-- Combine user badge info with high ranking answer user info
HighPerformers as (
    select 
        autq.UserId,
        autq.DisplayName,
        autq.TopRankedQuestionsCount,
        autq.TotalBadges,
        autq.HasGold,
        autq.HasSilver,
        autq.HasBronze,
        coalesce(uas.TotalBounties,0) as TotalBountiesAwarded,
        coalesce(uas.TotalScore,0) as TotalAnswerScore
    from ActiveUsersTopQuestions autq
    left join (
        select 
            p.OwnerUserId,
            sum(coalesce(v.TotalBounty,0)) as TotalBounties,
            sum(coalesce(p.Score,0)) as TotalScore
        from Posts p
        left join PostVoteStats v on v.PostId = p.Id
        where p.PostTypeId = 2
        group by p.OwnerUserId
    ) uas on uas.OwnerUserId = autq.UserId
    inner join HighRankedAnswerUsers hru on hru.UserId = autq.UserId
)
select 
    hp.UserId,
    hp.DisplayName,
    hp.TopRankedQuestionsCount,
    hp.TotalBadges,
    hp.HasGold,
    hp.HasSilver,
    hp.HasBronze,
    hp.TotalBountiesAwarded,
    hp.TotalAnswerScore,
    (select count(distinct qd.DuplicateQuestionId) from QuestionDuplicates qd where qd.OriginalQuestionId in (
        select p.Id from Posts p where p.OwnerUserId = hp.UserId and p.PostTypeId = 1
    )) as TotalDuplicatesReported,
    case 
        when hp.HasGold = 1 then 'Gold Contributor'
        when hp.HasSilver = 1 then 'Silver Contributor'
        when hp.HasBronze = 1 then 'Bronze Contributor'
        else 'No Badge' 
    end as ContributorTier,
    string_agg(distinct tt.Tag, ', ' order by tt.TagCount desc) as TopTagsContributed
from HighPerformers hp
left join UserTagIntersection uti on uti.UserId = hp.UserId
left join TopTags tt on tt.Tag = uti.Tag
group by hp.UserId, hp.DisplayName, hp.TopRankedQuestionsCount, hp.TotalBadges, hp.HasGold, hp.HasSilver, hp.HasBronze, hp.TotalBountiesAwarded, hp.TotalAnswerScore
order by hp.TopRankedQuestionsCount desc, hp.TotalAnswerScore desc
limit 100;