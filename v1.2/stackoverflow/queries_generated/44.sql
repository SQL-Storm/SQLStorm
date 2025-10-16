-- {"query": "44.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1721} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> all(r.Path)
    where t2.IsRequired = 1 and t2.Count < r.Count
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.OwnerUserId as QuestionOwnerId,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnswersWithOwner,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveScoreAnswers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId
),
PostWithVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        coalesce(v.Favorites, 0) as Favorites
    from Posts p
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes,
            sum(case when VoteTypeId = 5 then 1 else 0 end) as Favorites
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
),
TopQuestionsWithAnswers as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        pas.AnswerCount,
        pas.MaxAnswerScore,
        pas.AvgAnswerScore,
        pas.PositiveScoreAnswers,
        p.UpVotes,
        p.DownVotes,
        p.Favorites,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        row_number() over (partition by p.Tags order by p.Score desc, p.ViewCount desc) as TagRank
    from PostWithVotes p
    join PostAnswerStats pas on pas.QuestionId = p.Id
    left join UserReputationStats u on u.UserId = p.OwnerUserId
    where p.PostTypeId = 1
      and pas.AnswerCount > 0
      and p.Score > 5
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
QuestionsWithCloseReasons as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        ph.CreationDate as CloseDate,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserUserName
    from PostHistory ph
    join CloseReasonTypes cr on cr.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
FinalResult as (
    select
        tq.Id as QuestionId,
        tq.Title,
        tq.Tags,
        tq.Score,
        tq.ViewCount,
        tq.CreationDate,
        tq.AnswerCount,
        tq.MaxAnswerScore,
        round(tq.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
        tq.PositiveScoreAnswers,
        tq.UpVotes,
        tq.DownVotes,
        tq.Favorites,
        tq.OwnerName,
        tq.OwnerReputation,
        tq.GoldBadges,
        tq.SilverBadges,
        tq.BronzeBadges,
        coalesce(dc.DuplicateCount, 0) as DuplicateCount,
        cr.CloseReason,
        cr.CloseDate,
        cr.CloserUserName,
        dense_rank() over (order by tq.Score desc, tq.ViewCount desc) as OverallRank,
        case
            when tq.Score > 50 and tq.ViewCount > 10000 then 'Hot'
            when tq.Score between 20 and 50 then 'Warm'
            else 'Cold'
        end as PopularityCategory,
        -- Complex string manipulation: extract first tag from Tags string (format: <tag1><tag2><tag3>)
        substring(tq.Tags from '<([^>]+)>') as FirstTag,
        -- NULL logic: if OwnerName is null, fallback to 'Community'
        coalesce(tq.OwnerName, 'Community') as DisplayOwnerName
    from TopQuestionsWithAnswers tq
    left join (
        select
            PostId,
            count(*) as DuplicateCount
        from DuplicateLinks
        group by PostId
    ) dc on dc.PostId = tq.Id
    left join QuestionsWithCloseReasons cr on cr.PostId = tq.Id
)
select
    fr.QuestionId,
    fr.Title,
    fr.FirstTag,
    fr.Tags,
    fr.Score,
    fr.ViewCount,
    fr.AnswerCount,
    fr.MaxAnswerScore,
    fr.AvgAnswerScore,
    fr.PositiveScoreAnswers,
    fr.UpVotes,
    fr.DownVotes,
    fr.Favorites,
    fr.DisplayOwnerName,
    fr.OwnerReputation,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.DuplicateCount,
    fr.CloseReason,
    fr.CloseDate,
    fr.CloserUserName,
    fr.OverallRank,
    fr.PopularityCategory
from FinalResult fr
where fr.OverallRank <= 100
order by fr.OverallRank;