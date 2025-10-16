-- {"query": "431.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1644} 
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
    where t2.IsRequired = 1 and r.Level < 3
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
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as RepRank,
        count(*) over () as TotalUsers
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreation,
        a.Score as AnswerScore,
        au.DisplayName as AnswerOwnerName,
        au.Reputation as AnswerOwnerReputation,
        case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAcceptedAnswer,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = q.OwnerUserId
    left join Users au on au.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.Score > 10 and q.ViewCount > 1000
),
FilteredTopAnswers as (
    select *
    from TopQuestionsWithAnswers
    where AnswerRank <= 3
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserCommentActivity as (
    select
        c.UserId,
        u.DisplayName,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        sum(case when length(c.Text) > 100 then 1 else 0 end) as LongComments
    from Comments c
    join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
),
UserVoteSummary as (
    select
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesCast,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesCast,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoritesGiven
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(uca.CommentCount,0) as TotalComments,
        coalesce(uca.LongComments,0) as LongComments,
        coalesce(uvs.UpVotesCast,0) as UpVotesCast,
        coalesce(uvs.DownVotesCast,0) as DownVotesCast,
        coalesce(uvs.FavoritesGiven,0) as FavoritesGiven,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges
    from Users u
    left join UserCommentActivity uca on uca.UserId = u.Id
    left join UserVoteSummary uvs on uvs.UserId = u.Id
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedPostsCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicatePostsCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
)
select
    q.QuestionId,
    q.Title,
    q.QuestionCreation,
    q.QuestionScore,
    q.ViewCount,
    q.Tags,
    q.OwnerName,
    q.OwnerReputation,
    q.AnswerId,
    q.AnswerCreation,
    q.AnswerScore,
    q.AnswerOwnerName,
    q.AnswerOwnerReputation,
    q.IsAcceptedAnswer,
    coalesce(cr.CloseReasonName, 'Open') as CloseReason,
    coalesce(cr.CloseDate, null) as CloseDate,
    pls.LinkedPostsCount,
    pls.DuplicatePostsCount,
    uas.TotalComments,
    uas.LongComments,
    uas.UpVotesCast,
    uas.DownVotesCast,
    uas.FavoritesGiven,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    rh.Level as TagHierarchyLevel,
    rh.Path as TagHierarchyPath
from FilteredTopAnswers q
left join QuestionCloseReasons cr on cr.PostId = q.QuestionId
left join PostLinkSummary pls on pls.PostId = q.QuestionId
left join UserActivitySummary uas on uas.Id = q.OwnerUserId
left join RecursiveTagHierarchy rh on rh.TagName = any(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><'))
where q.QuestionCreation > (current_date - interval '2 years')
order by q.QuestionScore desc, q.ViewCount desc, q.AnswerScore desc
limit 100;