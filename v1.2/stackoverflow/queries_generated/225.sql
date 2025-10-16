-- {"query": "225.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1461} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id + 1
    where r.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vb.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vb.DownVotes),0) as TotalDownVotes,
        max(b.Date) as LastBadgeDate,
        string_agg(distinct b.Name, ', ') filter (where b.Class = 1) as GoldBadges,
        string_agg(distinct b.Name, ', ') filter (where b.Class = 2) as SilverBadges,
        string_agg(distinct b.Name, ', ') filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vb on vb.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreDenseRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
TopPostsWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.ScoreRank,
        p.ScoreDenseRank,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from PostScoreRanks p
    left join Comments c on c.PostId = p.Id
    where p.ScoreRank <= 100
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.ScoreRank, p.ScoreDenseRank
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 1) as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 3) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
),
UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldCount,
        count(*) filter (where b.Class = 2) as SilverCount,
        count(*) filter (where b.Class = 3) as BronzeCount
    from Badges b
    group by b.UserId
),
FinalResult as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionsAsked,
        u.AnswersGiven,
        u.CommentsMade,
        u.TotalUpVotes,
        u.TotalDownVotes,
        coalesce(ub.GoldCount,0) as GoldBadgesCount,
        coalesce(ub.SilverCount,0) as SilverBadgesCount,
        coalesce(ub.BronzeCount,0) as BronzeBadgesCount,
        p.Id as TopPostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        p.Score as PostScore,
        p.ViewCount as PostViewCount,
        p.CommentCount,
        p.LastCommentDate,
        p.Commenters,
        pls.LinkedCount,
        pls.DuplicateCount,
        -- Complex string expression: extract first tag from Tags array
        case
            when p.Tags is not null then
                substring(
                    split_part(
                        regexp_replace(p.Tags, '[<>]', '', 'g'),
                        ' ',
                        1
                    ) from 1 for 35
                )
            else null
        end as FirstTag,
        -- Complex calculation: weighted score with null logic
        (p.Score * 0.7 + coalesce(p.ViewCount,0) * 0.2 + coalesce(p.CommentCount,0) * 0.1) as WeightedScore,
        -- Window function: rank of user by reputation
        rank() over (order by u.Reputation desc) as UserReputationRank,
        -- Correlated subquery: count of answers accepted for user's questions
        (
            select count(*)
            from Posts a
            where a.PostTypeId = 2
              and a.OwnerUserId = u.UserId
              and exists (
                select 1 from Posts q where q.AcceptedAnswerId = a.Id and q.OwnerUserId = u.UserId
              )
        ) as AcceptedAnswersCount
    from UserActivity u
    left join TopPostsWithComments p on p.OwnerUserId = u.UserId
    left join PostLinkSummary pls on pls.PostId = p.Id
    left join UserBadgeCounts ub on ub.UserId = u.UserId
    where u.Reputation > 1000
)
select *
from FinalResult
where WeightedScore > 10
order by UserReputationRank, WeightedScore desc
limit 50;