-- {"query": "2271.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2131} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Title,
        p.Tags,
        p.CreationDate as PostCreationDate,
        ph.Id as LastEditHistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate as LastEditDate,
        row_number() over (partition by p.Id order by ph.CreationDate desc) as EditRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id
    where u.Reputation > 1000
),
FilteredActivities as (
    select *
    from RecursiveUserActivity
    where EditRank = 1 or EditRank is null
),
TopPostsByTag as (
    select 
        unnest(string_to_array(substring(coalesce(Tags,'') from 2 for length(coalesce(Tags,'')) - 2), '><')) as Tag,
        Id as PostId,
        Score,
        ViewCount,
        AnswerCount,
        Title,
        OwnerUserId,
        CreationDate
    from Posts
    where PostTypeId = 1 and Tags is not null
),
TagAggregatedStats as (
    select
        Tag,
        count(distinct PostId) as QuestionCount,
        avg(Score) as AvgScore,
        avg(ViewCount) as AvgViews,
        avg(AnswerCount) as AvgAnswers,
        max(Score) as MaxScore,
        sum(case when CreationDate > current_date - interval '30 days' then 1 else 0 end) as RecentQuestionCount
    from TopPostsByTag
    group by Tag
),
UserBadgeSummary as (
    select
        UserId,
        count(case when Class = 1 then 1 else null end) as GoldBadges,
        count(case when Class = 2 then 1 else null end) as SilverBadges,
        count(case when Class = 3 then 1 else null end) as BronzeBadges,
        count(distinct Name) as DistinctBadges
    from Badges
    group by UserId
),
UserVoteStats as (
    select
        u.Id as UserId,
        coalesce(sum(case when vt.Name = 'UpMod' then 1 else 0 end),0) as UpVotes,
        coalesce(sum(case when vt.Name = 'DownMod' then 1 else 0 end),0) as DownVotes,
        coalesce(sum(case when vt.Name = 'AcceptedByOriginator' then 1 else 0 end),0) as AcceptedVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id
),
DuplicatedPosts as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        count(*) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId, pl.RelatedPostId
),
UserComplexMetrics as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        coalesce(b.DistinctBadges,0) as DistinctBadges,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(v.AcceptedVotes,0) as AcceptedVotes,
        p.TotalQuestions,
        p.TotalAnswers,
        coalesce(dp.DupCount,0) as TotalDuplicateLinks
    from Users u
    left join UserBadgeSummary b on b.UserId = u.Id
    left join UserVoteStats v on v.UserId = u.Id
    left join (
        select 
            OwnerUserId,
            count(case when PostTypeId=1 then 1 else null end) as TotalQuestions,
            count(case when PostTypeId=2 then 1 else null end) as TotalAnswers
        from Posts
        group by OwnerUserId
    ) p on p.OwnerUserId = u.Id
    left join (
        select 
            OwnerUserId,
            count(*) as DupCount
        from Posts
        join DuplicatedPosts dp on dp.PostId = Posts.Id
        group by OwnerUserId
    ) dp on dp.OwnerUserId = u.Id
),
RankedUserPosts as (
    select 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score, 
        p.ViewCount,
        p.AnswerCount,
        p.Title,
        p.Tags,
        rank() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as PostRank,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostNum
    from Posts p
    where p.PostTypeId in (1,2)
),
AnswersWithQuestionStats as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerUserId,
        q.OwnerUserId as QuestionUserId,
        a.Score as AnswerScore,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AnswerCount as QuestionAnswerCount,
        a.CreationDate as AnswerCreation,
        q.CreationDate as QuestionCreation,
        case 
            when a.Score >= q.Score then 1
            else 0 
        end as AnswerBetterThanQuestion
    from Posts a
    join Posts q on q.Id = a.ParentId
    where a.PostTypeId = 2 and q.PostTypeId = 1
),
ComplexUserAnswerStats as (
    select 
        AnswerUserId,
        count(*) as TotalAnswers,
        sum(case when AnswerBetterThanQuestion = 1 then 1 else 0 end) as AnswersBetterThanQuestionCount,
        avg(a.AnswerScore * 1.0 / NULLIF(q.Score,0)) as AvgAnswerQuestionScoreRatio,
        avg(a.AnswerScore) as AvgAnswerScore,
        max(a.AnswerScore) as MaxAnswerScore,
        min(a.AnswerScore) as MinAnswerScore,
        avg(q.ViewCount) as AvgQuestionViewCount
    from AnswersWithQuestionStats a
    join Posts q on q.Id = a.QuestionId
    group by AnswerUserId
)
select 
    u.UserId,
    coalesce(u.DisplayName, 'Anonymous') as DisplayName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.DistinctBadges,
    u.UpVotes,
    u.DownVotes,
    u.AcceptedVotes,
    u.TotalQuestions,
    u.TotalAnswers,
    u.TotalDuplicateLinks,
    ca.TotalAnswers,
    ca.AnswersBetterThanQuestionCount,
    ca.AvgAnswerQuestionScoreRatio,
    ca.AvgAnswerScore,
    ca.MaxAnswerScore,
    ca.MinAnswerScore,
    ca.AvgQuestionViewCount,
    tas.Tag,
    tas.QuestionCount,
    tas.AvgScore as TagAvgScore,
    tas.AvgViews as TagAvgViews,
    tas.RecentQuestionCount,
    rp.PostId,
    rp.PostTypeId,
    rp.Score as PostScore,
    rp.ViewCount as PostViewCount,
    rp.AnswerCount as PostAnswerCount,
    rp.Title as PostTitle,
    case 
        when rp.PostRank <=3 then 'Top3'
        when rp.PostRank <=10 then 'Top10'
        else 'Others'
    end as PostRankCategory,
    -- String expression combining title length and verbatim tag presence
    length(rp.Title) + coalesce(array_position(string_to_array(coalesce(rp.Tags,''), '><'), 'sql'),0) * 10 as TitleTagScore,
    -- Null logic with coalesce
    coalesce(rp.Tags, '<no tags>') as PostTags,
    -- Correlated subquery: count comments on post where comment score > average comment score for that post
    (select count(*) from Comments c where c.PostId = rp.PostId and c.Score > (
        select avg(c2.Score) from Comments c2 where c2.PostId = rp.PostId and c2.Score is not null
    )) as HighScoringCommentsOnPost,
    -- Window function over posts per user for rank of view count
    rank() over (partition by rp.OwnerUserId order by rp.ViewCount desc nulls last) as ViewCountRankPerUser,
    -- Outer join example: last edit user display name for posts
    ph.UserDisplayName as LastEditorDisplayName,
    ph.CreationDate as LastEditDate
from UserComplexMetrics u
left join ComplexUserAnswerStats ca on ca.AnswerUserId = u.UserId
left join TagAggregatedStats tas on tas.Tag in (
    select unnest(string_to_array(coalesce(u2.Tags,''),'><')) from Posts u2 where u2.OwnerUserId = u.UserId limit 1
)
left join RankedUserPosts rp on rp.OwnerUserId = u.UserId and rp.PostRank <= 10
left join lateral (
    select ph.UserDisplayName, ph.CreationDate
    from PostHistory ph
    where ph.PostId = rp.PostId
    order by ph.CreationDate desc
    limit 1
) ph on true
where u.Reputation > 5000
order by u.Reputation desc, u.GoldBadges desc, rp.PostScore desc
limit 100;