-- {"query": "2601.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1340} 
with RankedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.Title,
        -- categorize questions by decade of creation
        date_part('year', p.CreationDate)::int/10*10 as Decade,
        -- calculate ratio of favorites to views safely
        case when p.ViewCount > 0 then p.FavoriteCount::float / p.ViewCount else null end as FavsToViewsRatio,
        -- count of distinct users who commented on this post
        (select count(distinct c.UserId) from Comments c where c.PostId = p.Id) as DistinctCommenters,
        -- latest edit date
        p.LastEditDate,
        -- window function: rank questions within same decade by score descending
        rank() over (partition by date_part('year', p.CreationDate)::int/10*10 order by p.Score desc nulls last) as DecadeScoreRank
    from Posts p
    where p.PostTypeId = 1 -- only questions
),
UserBadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
UserActivitySummary as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        -- count of posts by user
        (select count(*) from Posts p where p.OwnerUserId = u.Id) as PostsCount,
        -- average score of posts by user
        (select avg(p.Score) from Posts p where p.OwnerUserId = u.Id) as AvgPostScore,
        -- last activity date from posts or comments whichever is later
        greatest(
            coalesce((select max(p.LastActivityDate) from Posts p where p.OwnerUserId = u.Id), TIMESTAMP '1970-01-01'),
            coalesce((select max(c.CreationDate) from Comments c where c.UserId = u.Id), TIMESTAMP '1970-01-01')
        ) as LastKnownActivity
    from Users u
    left join UserBadgeCounts ub on ub.UserId = u.Id
),
TopQuestionsWithDuplicates as (
    select 
        rp.Id as QuestionId,
        rp.Title,
        rp.OwnerUserId,
        ua.DisplayName as OwnerName,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.FavoriteCount,
        rp.Tags,
        rp.Decade,
        rp.DecadeScoreRank,
        rp.DistinctCommenters,
        rp.FavsToViewsRatio,
        -- check if question is duplicated by another question (duplicate links)
        exists (
            select 1 from PostLinks pl
            join Posts dup on dup.Id = pl.PostId
            where pl.RelatedPostId = rp.Id 
              and pl.LinkTypeId = 3 -- duplicate link type
              and dup.PostTypeId = 1
        ) as IsDuplicated,
        -- last edit date
        rp.LastEditDate
    from RankedPosts rp
    join UserActivitySummary ua on ua.Id = rp.OwnerUserId
    where rp.DecadeScoreRank <= 50 -- top 50 questions per decade by score
),
UserTopAnswers as (
    select 
        u.Id as UserId,
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        dense_rank() over (partition by u.Id order by p.Score desc nulls last) as ScoreRank
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where p.PostTypeId = 2 -- answers
),
UserHighScoreAnswerUsers as (
    select distinct UserId
    from UserTopAnswers
    where ScoreRank = 1 and Score > 100 -- users' top answers with score > 100
),
QuestionsWithUserAnswerInfo as (
    select 
        tq.*,
        ua.Score as UserTopAnswerScore,
        ua.AnswerId
    from TopQuestionsWithDuplicates tq
    left join UserTopAnswers ua on ua.QuestionId = tq.QuestionId and ua.ScoreRank = 1
),
FinalFilteredQuestions as (
    select *
    from QuestionsWithUserAnswerInfo
    where (FavsToViewsRatio is not null and FavsToViewsRatio > 0.01) -- some attraction ratio
      and DistinctCommenters >= 3
      and Score > 10
      and (IsDuplicated = false or IsDuplicated is null)
)

select 
    ffq.QuestionId,
    ffq.Title,
    left(ffq.Tags, 100) as SampleTags,
    ffq.Score,
    ffq.ViewCount,
    ffq.AnswerCount,
    ffq.FavoriteCount,
    round(ffq.FavsToViewsRatio::numeric,4) as FavsToViewsRatio,
    ffq.DistinctCommenters,
    ffq.Decade,
    ffq.DecadeScoreRank,
    ffq.OwnerUserId,
    ffq.OwnerName,
    ffq.UserTopAnswerScore,
    ffq.AnswerId,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.Reputation,
    ua.PostsCount,
    ua.AvgPostScore,
    ua.LastKnownActivity,
    -- calculate days since last edit, null if never edited
    case when ffq.LastEditDate is not null then
        (current_date - cast(ffq.LastEditDate as date))
    else null end as DaysSinceLastEdit
from FinalFilteredQuestions ffq
left join UserActivitySummary ua on ua.Id = ffq.OwnerUserId
order by ffq.Decade desc, ffq.Score desc
limit 100;