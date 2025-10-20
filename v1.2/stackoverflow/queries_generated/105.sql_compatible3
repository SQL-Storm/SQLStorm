with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar) as Path
    from Tags t
    where coalesce(t.IsModeratorOnly, false) = false and coalesce(t.IsRequired, false) = false

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1 as Level,
        r.Path || ' > ' || t.TagName as Path
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
        u.Id,
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
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName,
        dense_rank() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
      and q.CreationDate >= (cast('2024-10-01' as date) - interval '365 days')
),
FilteredTopAnswers as (
    select *
    from TopQuestionsWithAnswers
    where AnswerRank = 1
),
QuestionCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as ClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as ReopenedDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
),
AnswerVoteStats as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        count(*) as TotalVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionsCount,
        count(case when p.PostTypeId = 2 then 1 end) as AnswersCount,
        count(c.Id) as CommentsCount,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        row_number() over (order by u.Reputation desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as PostOwner,
        u2.DisplayName as RelatedPostOwner
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p on p.Id = pl.PostId
    join Users u on u.Id = p.OwnerUserId
    join Posts rp on rp.Id = pl.RelatedPostId
    join Users u2 on u2.Id = rp.OwnerUserId
),
QuestionTagExplode as (
    select
        p.Id as QuestionId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagQuestionCounts as (
    select
        qte.Tag,
        count(distinct qte.QuestionId) as QuestionCount,
        avg(q.Score) as AvgQuestionScore,
        max(q.ViewCount) as MaxViewCount
    from QuestionTagExplode qte
    join Posts q on q.Id = qte.QuestionId
    group by qte.Tag
),
UserTopTags as (
    select
        ua.Id as UserId,
        qte.Tag,
        count(*) as AnswersInTag,
        row_number() over (partition by ua.Id order by count(*) desc) as TagRank
    from Users ua
    join Posts p on p.OwnerUserId = ua.Id and p.PostTypeId = 2
    join QuestionTagExplode qte on qte.QuestionId = p.ParentId
    group by ua.Id, qte.Tag
)
select
    urs.Id as UserId,
    urs.DisplayName,
    urs.Reputation,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.CommentsCount,
    ua.LastPostDate,
    ua.LastCommentDate,
    ftq.QuestionId,
    ftq.Title as TopQuestionTitle,
    ftq.QuestionCreationDate,
    ftq.QuestionScore,
    ftq.ViewCount as QuestionViewCount,
    ftq.AnswerId as TopAnswerId,
    ftq.AnswerCreationDate,
    ftq.AnswerScore,
    ftq.AnswerOwnerUserId,
    ftq.AnswerOwnerDisplayName,
    aci.ClosedDate,
    aci.ReopenedDate,
    aci.CloseReasonId,
    avs.UpVotes as AnswerUpVotes,
    avs.DownVotes as AnswerDownVotes,
    avs.TotalVotes as AnswerTotalVotes,
    dl.PostId as DuplicatePostId,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.PostOwner as DuplicatePostOwner,
    dl.RelatedPostOwner as DuplicateRelatedPostOwner,
    tqc.Tag as PopularTag,
    tqc.QuestionCount as PopularTagQuestionCount,
    tqc.AvgQuestionScore as PopularTagAvgScore,
    tqc.MaxViewCount as PopularTagMaxViewCount,
    ut.Tag as UserTopTag,
    ut.AnswersInTag as UserAnswersInTopTag
from UserReputationStats urs
left join UserActivityWindow ua on ua.Id = urs.Id
left join FilteredTopAnswers ftq on ftq.AnswerOwnerUserId = urs.Id
left join QuestionCloseInfo aci on aci.PostId = ftq.QuestionId
left join AnswerVoteStats avs on avs.PostId = ftq.AnswerId
left join DuplicateLinks dl on dl.PostId = ftq.QuestionId
left join TagQuestionCounts tqc on tqc.Tag = (
    select Tag
    from QuestionTagExplode
    where QuestionId = ftq.QuestionId
    limit 1
)
left join UserTopTags ut on ut.UserId = urs.Id and ut.TagRank = 1
where urs.Reputation > 1000
group by
    urs.Id,
    urs.DisplayName,
    urs.Reputation,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.CommentsCount,
    ua.LastPostDate,
    ua.LastCommentDate,
    ftq.QuestionId,
    ftq.Title,
    ftq.QuestionCreationDate,
    ftq.QuestionScore,
    ftq.ViewCount,
    ftq.AnswerId,
    ftq.AnswerCreationDate,
    ftq.AnswerScore,
    ftq.AnswerOwnerUserId,
    ftq.AnswerOwnerDisplayName,
    aci.ClosedDate,
    aci.ReopenedDate,
    aci.CloseReasonId,
    avs.UpVotes,
    avs.DownVotes,
    avs.TotalVotes,
    dl.PostId,
    dl.RelatedPostId,
    dl.PostOwner,
    dl.RelatedPostOwner,
    tqc.Tag,
    tqc.QuestionCount,
    tqc.AvgQuestionScore,
    tqc.MaxViewCount,
    ut.Tag,
    ut.AnswersInTag
order by urs.Reputation desc, ftq.QuestionScore desc
limit 100;