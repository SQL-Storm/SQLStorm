-- {"query": "209.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1530} 
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
    where t2.IsRequired = 1 and t2.Count > 10
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
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on u.Id = ubc_gold.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on u.Id = ubc_silver.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on u.Id = ubc_bronze.UserId and ubc_bronze.Class = 3
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.Score > 10 and p.AnswerCount > 0
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAcceptedAnswer
    from Posts a
    join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    where a.PostTypeId = 2
    group by a.ParentId, q.AcceptedAnswerId
),
QuestionComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.UserId is null then 1 else 0 end) as AnonymousComments
    from Comments c
    group by c.PostId
),
PostLinkDuplicates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '365 days' preceding and current row) as PostsLastYear
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
ComplexUserStats as (
    select
        ua.UserId,
        ua.DisplayName,
        max(ua.PostsLast30Days) as MaxPosts30Days,
        max(ua.PostsLastYear) as MaxPostsYear,
        ur.Reputation,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        case
            when ur.Reputation > 100000 then 'Legendary'
            when ur.Reputation > 10000 then 'Expert'
            when ur.Reputation > 1000 then 'Intermediate'
            else 'Beginner'
        end as ReputationLevel
    from UserActivityWindow ua
    join UserReputationStats ur on ua.UserId = ur.UserId
    group by ua.UserId, ua.DisplayName, ur.Reputation, ur.GoldBadges, ur.SilverBadges, ur.BronzeBadges
)
select
    tq.Id as QuestionId,
    tq.Title,
    tq.OwnerUserId,
    tq.OwnerName,
    tq.CreationDate as QuestionCreation,
    tq.Score as QuestionScore,
    tq.ViewCount,
    tq.Tags,
    as1.TotalAnswers,
    as1.AvgAnswerScore,
    as1.MaxAnswerScore,
    as1.HasAcceptedAnswer,
    qc.CommentCount as QuestionCommentCount,
    qc.AnonymousComments as QuestionAnonymousComments,
    pld.DuplicateCount,
    cu.MaxPosts30Days,
    cu.MaxPostsYear,
    cu.Reputation,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.ReputationLevel,
    -- Complex string expression combining tags and user info
    concat_ws(' | ',
        substring(tq.Title from 1 for 50),
        coalesce(cu.DisplayName, 'Unknown User'),
        'Tags: ' || coalesce(tq.Tags, 'None'),
        'Answers: ' || coalesce(as1.TotalAnswers::text, '0'),
        'Duplicates: ' || coalesce(pld.DuplicateCount::text, '0')
    ) as SummaryInfo
from TopQuestions tq
left join AnswerStats as1 on tq.Id = as1.QuestionId
left join QuestionComments qc on tq.Id = qc.PostId
left join PostLinkDuplicates pld on tq.Id = pld.PostId
left join ComplexUserStats cu on tq.OwnerUserId = cu.UserId
where
    (tq.Score > 50 or as1.MaxAnswerScore > 20)
    and (cu.ReputationLevel in ('Expert', 'Legendary'))
    and exists (
        select 1 from RecursiveTagHierarchy rth
        where rth.TagName = any(string_to_array(replace(replace(tq.Tags, '<', ''), '>', ''), ' '))
        and rth.Level <= 3
    )
order by tq.Score desc, as1.MaxAnswerScore desc, cu.Reputation desc
limit 100;