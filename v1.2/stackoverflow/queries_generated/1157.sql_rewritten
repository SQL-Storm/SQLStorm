-- {"query": "1157.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1245} 
with UserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        coalesce(sum(vp.VoteCount),0) as TotalVotesOnPosts,
        coalesce(sum(ans.Score),0) as TotalScoreOnAnswers,
        max(ph.MaxEdits) as MaxEditHistoryDepth
    from
        Users u
    left join
        Badges b on b.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            count(v.Id) as VoteCount
        from Posts p
        left join Votes v on v.PostId = p.Id
        where p.OwnerUserId is not null and p.OwnerUserId <> -1
        group by p.OwnerUserId
    ) vp on vp.OwnerUserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(p.Score) as Score
        from Posts p
        where p.PostTypeId = 2 -- answers only
          and p.OwnerUserId is not null and p.OwnerUserId <> -1
        group by p.OwnerUserId
    ) ans on ans.OwnerUserId = u.Id
    left join (
        select
            ph.UserId,
            ph.PostId,
            count(distinct ph.Id) as MaxEdits
        from PostHistory ph
        where ph.UserId is not null
        group by ph.UserId, ph.PostId
    ) ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RecentHighlyActiveUsers as (
    select
        UserId,
        DisplayName,
        Reputation,
        BadgeCount,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        TotalVotesOnPosts,
        TotalScoreOnAnswers,
        MaxEditHistoryDepth,
        row_number() over (order by Reputation desc, BadgeCount desc) as rank
    from UserStats
    where Reputation > 10000 and BadgeCount > 5
      and MaxEditHistoryDepth > 10
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        rhu.DisplayName as OwnerName,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc) as rn
    from Posts p
    join RecentHighlyActiveUsers rhu on rhu.UserId = p.OwnerUserId
    where p.PostTypeId = 1 -- questions only
      and p.CreationDate > cast('2024-10-01' as date) - interval '1 year'
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(*) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3 -- duplicates
    group by pl.PostId
),
QuestionsWithDupCounts as (
    select
        tq.*,
        coalesce(dlc.DuplicateCount, 0) as DuplicateCount
    from TopQuestions tq
    left join DuplicateLinkCounts dlc on dlc.PostId = tq.Id
),
QuestionDetails as (
    select
        qwc.*,
        (select count(c.Id)
         from Comments c
         where c.PostId = qwc.Id and c.CreationDate > qwc.CreationDate and c.Score > 0) as PositiveCommentCountSinceCreation,
        (select max(ph.CreationDate)
         from PostHistory ph
         where ph.PostId = qwc.Id and ph.PostHistoryTypeId in (4,5,6)) as LastEditDate,
        (select sum(vt.VoteCount)
         from (
            select v.VoteTypeId, count(*) as VoteCount
            from Votes v
            where v.PostId = qwc.Id
            group by v.VoteTypeId
         ) vt
         where vt.VoteTypeId in (2,5)) as UpVotesPlusFavorites
    from QuestionsWithDupCounts qwc
),
FinalResultSet as (
    select
        qd.Id as QuestionId,
        qd.Title,
        qd.OwnerUserId,
        qd.OwnerName,
        qd.Score,
        qd.ViewCount,
        qd.AnswerCount,
        qd.DuplicateCount,
        qd.PositiveCommentCountSinceCreation,
        qd.LastEditDate,
        qd.UpVotesPlusFavorites,
        u.Reputation as OwnerReputation,
        case
            when qd.Score > 10 and qd.AnswerCount > 3 then 'Hot'
            when qd.Score between 5 and 10 then 'Trending'
            when qd.DuplicateCount > 0 then 'Duplicate'
            else 'Normal'
        end as QuestionStatus,
        concat(
            coalesce(u.DisplayName,'[deleted]'),
            ' (Reputation:', coalesce(cast(u.Reputation as varchar), '0'),
            ', Badges:', coalesce(cast(us.BadgeCount as varchar), '0'), ')'
        ) as OwnerSummary
    from QuestionDetails qd
    left join Users u on u.Id = qd.OwnerUserId
    left join UserStats us on us.UserId = qd.OwnerUserId
    where qd.OwnerUserId is not null
)
select * from FinalResultSet
where QuestionStatus in ('Hot', 'Trending')
order by UpVotesPlusFavorites desc nulls last, Score desc, ViewCount desc
limit 100;