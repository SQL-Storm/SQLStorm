-- {"query": "2840.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1811} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        array[t.TagName] as TagPath,
        1 as Level
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        rth.TagPath || t.TagName,
        rth.Level + 1
    from Tags t
    join RecursiveTagHierarchy rth on t.Id != rth.Id
    where t.IsRequired = 1 and not t.TagName = any(rth.TagPath) and rth.Level < 3
),
LatestUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        max(coalesce(p.LastActivityDate, c.CreationDate, ph.CreationDate)) as LastActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
UserBadgesSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        bool_or(b.TagBased = 1) as HasTagBasedBadge
    from Badges b
    group by b.UserId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate as QuestionCreationDate,
        q.AcceptedAnswerId,
        q.OwnerUserId as QuestionOwner,
        q.Score as QuestionScore,
        q.ViewCount,
        count(distinct a.Id) as AnswerCount,
        avg(coalesce(a.Score, 0)) as AvgAnswerScore,
        sum(coalesce(a.Score, 0)) as TotalAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.CreationDate, q.AcceptedAnswerId, q.OwnerUserId, q.Score, q.ViewCount
),
PostCommentsAgg as (
    select
        p.Id as PostId,
        count(c.Id) as CommentCount,
        string_agg(distinct c.UserDisplayName || ': ' || substring(c.Text, 1, 30), ' | ') as CommentPreview
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id
),
PostLinkDuplicates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
UserTopPosts as (
    select distinct on (p.OwnerUserId)
        p.OwnerUserId,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as RankTopPost
    from Posts p
    where p.OwnerUserId is not null and p.PostTypeId in (1,2)
    order by p.OwnerUserId, p.Score desc, p.ViewCount desc
),
UserActivityWindow as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Location,
        ua.LastActivity,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        ub.HasTagBasedBadge,
        utp.PostId as TopPostId,
        utp.Score as TopPostScore,
        utp.ViewCount as TopPostViews,
        row_number() over (partition by ua.UserId order by ua.LastActivity desc) as ActivityRank
    from LatestUserActivity ua
    left join UserBadgesSummary ub on ub.UserId = ua.UserId
    left join UserTopPosts utp on utp.OwnerUserId = ua.UserId and utp.RankTopPost = 1
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        crt.Id as CloseReasonId,
        q.Title,
        q.OwnerUserId
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id::text = ph.Comment
    join Posts q on q.Id = ph.PostId
    where ph.PostHistoryTypeId = 10 and q.PostTypeId = 1
),
UserClosedQuestionCounts as (
    select
        OwnerUserId,
        count(Distinct PostId) as ClosedQuestionsCount,
        string_agg(Distinct CloseReason, ', ') as CloseReasons
    from ClosedQuestionsWithReasons
    group by OwnerUserId
)

select
    qas.QuestionId,
    qas.Title,
    -- Extract and count tags safely (tags format: <tag1><tag2><tag3>)
    array_length(string_to_array(trim(both '<>' from qas.Tags), '><'), 1) as NumberOfTags,
    qas.ViewCount,
    qas.QuestionScore,
    qas.AnswerCount,
    round(qas.AvgAnswerScore, 2) as AvgAnswerScore,
    coalesce(pld.DuplicateCount, 0) as DuplicateLinkCount,
    -- Show comment preview for question truncated
    substring(pca.CommentPreview from 1 for 100) as QuestionCommentPreview,
    -- Owner info
    ua.DisplayName as QuestionOwnerDisplayName,
    ua.Reputation as QuestionOwnerReputation,
    ua.Location as QuestionOwnerLocation,
    ub.GoldBadges as OwnerGoldBadges,
    ub.SilverBadges as OwnerSilverBadges,
    ub.BronzeBadges as OwnerBronzeBadges,
    -- Last activity on user ordered by window function rank
    ua.LastActivity,
    -- Accepted Answer info
    aa.Id as AcceptedAnswerId,
    aa.Score as AcceptedAnswerScore,
    -- Window function rank of user activity
    ua.ActivityRank,
    -- Closed question counts and reasons for owner
    ucc.ClosedQuestionsCount,
    ucc.CloseReasons,
    -- Complex calculated score combining multiple factors
    (
        qas.QuestionScore * 2
        + coalesce(qas.TotalAnswerScore, 0)
        + coalesce(pld.DuplicateCount, 0) * -3
        + coalesce(ucc.ClosedQuestionsCount, 0) * -10
        + coalesce(ub.GoldBadges, 0) * 5
        + coalesce(ub.SilverBadges, 0) * 2
        - coalesce(ua.Reputation, 0) / 1000
        + coalesce(ua.ActivityRank, 1) * -1.5
    ) as ComplexPopularityScore
from QuestionAnswerStats qas
left join Posts aa on aa.Id = qas.AcceptedAnswerId
left join PostCommentsAgg pca on pca.PostId = qas.QuestionId
left join PostLinkDuplicates pld on pld.PostId = qas.QuestionId
left join Users ua on ua.Id = qas.QuestionOwner
left join UserBadgesSummary ub on ub.UserId = qas.QuestionOwner
left join UserActivityWindow uaw on uaw.UserId = qas.QuestionOwner and uaw.ActivityRank <= 3
left join UserClosedQuestionCounts ucc on ucc.OwnerUserId = qas.QuestionOwner
where qas.AnswerCount > 0
  and qas.QuestionScore > 5
  and ua.Reputation >= 1000
  and (array_length(string_to_array(trim(both '<>' from qas.Tags), '><'), 1) between 2 and 5)
order by ComplexPopularityScore desc nulls last
limit 100;