-- {"query": "247.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1750} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        array[t.TagName] as Path
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
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id + 1
    where r.Level < 3
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
    left join UserBadgeCounts ubc_gold on u.Id = ubc_gold.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on u.Id = ubc_silver.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on u.Id = ubc_bronze.UserId and ubc_bronze.Class = 3
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.OwnerUserId,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswerCount,
        sum(case when a.Score <= 0 then 1 else 0 end) as NonPositiveAnswerCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId
),
PostVoteAggregates as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
),
UserRecentActivity as (
    select
        u.Id as UserId,
        max(p.LastActivityDate) as LastPostActivity,
        max(c.CreationDate) as LastCommentDate,
        max(v.CreationDate) as LastVoteDate,
        greatest(
            coalesce(max(p.LastActivityDate), timestamp '1970-01-01'),
            coalesce(max(c.CreationDate), timestamp '1970-01-01'),
            coalesce(max(v.CreationDate), timestamp '1970-01-01')
        ) as LastActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id
),
TopQuestionsWithDetails as (
    select
        pas.QuestionId,
        pas.Title,
        pas.QuestionCreationDate,
        pas.OwnerUserId,
        pas.TotalAnswers,
        pas.MaxAnswerScore,
        pas.AvgAnswerScore,
        pas.PositiveAnswerCount,
        pas.NonPositiveAnswerCount,
        pva.UpVotes,
        pva.DownVotes,
        pva.FavoriteVotes,
        pva.TotalBounty,
        qcr.CloseReason,
        ur.LastActivity,
        ur.LastPostActivity,
        ur.LastCommentDate,
        ur.LastVoteDate,
        ur.UserId as ActivityUserId,
        ur2.DisplayName as OwnerDisplayName,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        urs.Reputation,
        urs.ReputationRank,
        row_number() over (partition by pas.OwnerUserId order by pas.QuestionCreationDate desc) as OwnerQuestionRank
    from PostAnswerStats pas
    left join PostVoteAggregates pva on pas.QuestionId = pva.PostId
    left join QuestionCloseReasons qcr on pas.QuestionId = qcr.PostId
    left join UserRecentActivity ur on pas.OwnerUserId = ur.UserId
    left join Users ur2 on pas.OwnerUserId = ur2.Id
    left join UserReputationStats urs on pas.OwnerUserId = urs.UserId
    where pas.TotalAnswers > 0
)
select
    tqwd.QuestionId,
    tqwd.Title,
    tqwd.QuestionCreationDate,
    coalesce(tqwd.OwnerDisplayName, 'Anonymous') as OwnerDisplayName,
    tqwd.Reputation,
    tqwd.GoldBadges,
    tqwd.SilverBadges,
    tqwd.BronzeBadges,
    tqwd.TotalAnswers,
    tqwd.MaxAnswerScore,
    round(tqwd.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    tqwd.PositiveAnswerCount,
    tqwd.NonPositiveAnswerCount,
    tqwd.UpVotes,
    tqwd.DownVotes,
    tqwd.FavoriteVotes,
    tqwd.TotalBounty,
    coalesce(tqwd.CloseReason, 'Open') as CloseReason,
    tqwd.LastActivity,
    tqwd.OwnerQuestionRank,
    -- Complex string expression: concatenated tags from the question's Tags field
    string_agg(distinct unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')), ',' order by 1) as TagList,
    -- Window function: rank answers by score per question
    ans.Id as AnswerId,
    ans.Score as AnswerScore,
    ans.CreationDate as AnswerCreationDate,
    ans.OwnerUserId as AnswerOwnerUserId,
    ans.OwnerDisplayName as AnswerOwnerDisplayName,
    rank() over (partition by ans.ParentId order by ans.Score desc, ans.CreationDate asc) as AnswerRank,
    -- Correlated subquery: count comments on each answer
    (select count(*) from Comments c where c.PostId = ans.Id) as AnswerCommentCount,
    -- Outer join with PostLinks to find duplicates or linked posts
    pl.LinkTypeId,
    pl.RelatedPostId,
    lt.Name as LinkTypeName
from TopQuestionsWithDetails tqwd
join Posts p on p.Id = tqwd.QuestionId
join Posts ans on ans.ParentId = tqwd.QuestionId and ans.PostTypeId = 2
left join PostLinks pl on pl.PostId = tqwd.QuestionId
left join LinkTypes lt on pl.LinkTypeId = lt.Id
where tqwd.ReputationRank <= 100
order by tqwd.ReputationRank, tqwd.QuestionCreationDate desc, AnswerRank
limit 500;