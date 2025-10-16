-- {"query": "61.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1690} 
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
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id = r.Id + 1
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostScoreStats as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxScore,
        min(p.Score) filter (where p.PostTypeId in (1,2)) as MinScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeQuestions,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeAnswers,
        row_number() over (partition by u.Id order by p.CreationDate desc) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        p.Title,
        p.Tags,
        u.DisplayName as OwnerName
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where ph.CreationDate > current_date - interval '1 year'
),
TopVotedAnswers as (
    select distinct on (p.ParentId)
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        u.DisplayName as Answerer,
        p.CreationDate
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 2
    order by p.ParentId, p.Score desc, p.CreationDate asc
),
AnswerCommentsCount as (
    select
        c.PostId,
        count(*) as CommentCount
    from Comments c
    group by c.PostId
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
UserPostLinkDuplicates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateLinksCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedPostsCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ps.QuestionCount,
    ps.AnswerCount,
    ps.AvgScore,
    ps.MaxScore,
    ps.MinScore,
    ps.TotalQuestionViews,
    ua.CumulativeQuestions,
    ua.CumulativeAnswers,
    coalesce(ac.CommentCount, 0) as TotalCommentsOnTopAnswers,
    cq.CloseReason,
    cq.Title as ClosedQuestionTitle,
    cq.Tags as ClosedQuestionTags,
    cq.OwnerName as ClosedQuestionOwner,
    ur.ReputationRank,
    upld.DuplicateLinksCount,
    upld.LinkedPostsCount,
    -- Complex string expression with NULL logic and conditional concatenation
    case
        when u.WebsiteUrl is not null and length(u.WebsiteUrl) > 0 then
            'User Website: ' || u.WebsiteUrl || ' | Location: ' || coalesce(u.Location, 'Unknown')
        when u.Location is not null then
            'Location Only: ' || u.Location
        else
            'No Website or Location Provided'
    end as UserContactInfo,
    -- Window function example: rank of user's last post score among all posts by that user
    rank() over (partition by u.Id order by p.Score desc nulls last) as UserPostScoreRank,
    -- Correlated subquery with NULL logic: count of badges earned in last 30 days
    (
        select count(*)
        from Badges b2
        where b2.UserId = u.Id
          and b2.Date >= current_date - interval '30 days'
    ) as RecentBadgesCount,
    -- Set operator example: union of tags from closed questions and top voted answers' questions
    (
        select string_agg(distinct t.TagName, ', ')
        from Tags t
        where t.Id in (
            select unnest(string_to_array(replace(replace(cq.Tags, '<', ''), '>', ''), ' '))
            from ClosedQuestionsWithReasons cq
            where cq.OwnerName = u.DisplayName
            union
            select unnest(string_to_array(replace(replace(p.Tags, '<', ''), '>', ''), ' '))
            from Posts p
            join TopVotedAnswers tva on tva.QuestionId = p.Id
            where p.OwnerUserId = u.Id
        )
    ) as UserRelatedTags
from Users u
left join UserBadgeCounts ubc on ubc.UserId = u.Id
left join PostScoreStats ps on ps.OwnerUserId = u.Id
left join UserActivityWindow ua on ua.UserId = u.Id and ua.LastPostRank = 1
left join TopVotedAnswers tva on tva.Answerer = u.DisplayName
left join AnswerCommentsCount ac on ac.PostId = tva.AnswerId
left join ClosedQuestionsWithReasons cq on cq.OwnerName = u.DisplayName
left join UserReputationRank ur on ur.Id = u.Id
left join Posts p on p.OwnerUserId = u.Id
left join UserPostLinkDuplicates upld on upld.PostId = p.Id
where u.Reputation > 1000
order by ur.ReputationRank
limit 100;