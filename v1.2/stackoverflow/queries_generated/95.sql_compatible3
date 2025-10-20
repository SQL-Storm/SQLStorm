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
    where t.IsModeratorOnly = false and t.IsRequired = false
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
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsModeratorOnly = false and t2.IsRequired = false
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
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        max(p.CreationDate) filter (where p.PostTypeId in (1,2)) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ubc_gold.BadgeCount, ubc_silver.BadgeCount, ubc_bronze.BadgeCount
),
PostWithCommentsAndVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        coalesce(c.CommentCount,0) as TotalComments,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join (
        select
            v.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by v.PostId
    ) v on v.PostId = p.Id
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        p.TotalComments,
        p.UpVotes,
        p.DownVotes,
        p.HasAcceptedAnswer,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc, p.CreationDate desc) as RankByScore,
        rank() over (partition by p.PostTypeId order by p.CommentCount desc) as RankByComments,
        dense_rank() over (partition by p.PostTypeId order by p.FavoriteCount desc) as RankByFavorites
    from PostWithCommentsAndVotes p
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as OwnerDisplayName,
        p.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p on p.Id = pl.RelatedPostId
    left join Users u on u.Id = p.OwnerUserId
),
QuestionsWithCloseReasons as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes cr on cr.Id = cast(ph.Comment as integer)
    where ph.PostId in (select Id from Posts where PostTypeId = 1)
),
TopUsersQuestions as (
    select
        ua.UserId,
        ua.DisplayName,
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.CommentCount,
        p.CreationDate,
        p.ClosedDate,
        qcr.CloseReason,
        dup.RelatedPostId as DuplicateOfPostId,
        dup.RelatedPostTitle as DuplicateOfPostTitle
    from UserActivity ua
    join Posts p on p.OwnerUserId = ua.UserId and p.PostTypeId = 1
    left join QuestionsWithCloseReasons qcr on qcr.PostId = p.Id
    left join (
        select
            dl.PostId,
            dl.RelatedPostId,
            dl.RelatedPostTitle
        from DuplicateLinks dl
    ) dup on dup.PostId = p.Id
    where ua.Reputation > 10000 and ua.GoldBadges > 0
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        sum(case when p.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswerCount
    from Posts p
    join Posts q on q.Id = p.ParentId and q.PostTypeId = 1
    where p.PostTypeId = 2
    group by p.ParentId, q.AcceptedAnswerId
),
FinalResult as (
    select
        tuq.UserId,
        tuq.DisplayName,
        tuq.QuestionId,
        tuq.Title,
        tuq.Score as QuestionScore,
        tuq.ViewCount as QuestionViews,
        tuq.Tags,
        tuq.AnswerCount,
        tuq.FavoriteCount,
        tuq.CommentCount,
        tuq.CreationDate as QuestionCreationDate,
        tuq.ClosedDate,
        tuq.CloseReason,
        tuq.DuplicateOfPostId,
        tuq.DuplicateOfPostTitle,
        coalesce(a.AnswerCount,0) as TotalAnswers,
        coalesce(a.AvgAnswerScore,0) as AverageAnswerScore,
        coalesce(a.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(a.AcceptedAnswerCount,0) as AcceptedAnswerCount,
        ua.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.TotalPostScore,
        ua.LastPostDate
    from TopUsersQuestions tuq
    join AnswerStats a on a.QuestionId = tuq.QuestionId
    join UserActivity ua on ua.UserId = tuq.UserId
)
select
    fr.UserId,
    fr.DisplayName,
    fr.Reputation,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.QuestionsCount,
    fr.AnswersCount,
    fr.TotalPostScore,
    fr.LastPostDate,
    fr.QuestionId,
    fr.Title,
    fr.QuestionScore,
    fr.QuestionViews,
    fr.Tags,
    fr.AnswerCount,
    fr.FavoriteCount,
    fr.CommentCount,
    fr.QuestionCreationDate,
    fr.ClosedDate,
    fr.CloseReason,
    fr.DuplicateOfPostId,
    fr.DuplicateOfPostTitle,
    fr.TotalAnswers,
    fr.AverageAnswerScore,
    fr.MaxAnswerScore,
    fr.AcceptedAnswerCount,
    concat_ws(' | ',
        'Tags: ' || coalesce(fr.Tags, 'No Tags'),
        'Asked by: ' || coalesce(fr.DisplayName, 'Anonymous'),
        'Reputation: ' || fr.Reputation,
        'Gold Badges: ' || fr.GoldBadges,
        'Answers: ' || fr.TotalAnswers
    ) as SummaryInfo,
    rank() over (partition by fr.UserId order by fr.QuestionScore desc) as QuestionScoreRank,
    (
        select c.Text
        from Comments c
        where c.PostId = fr.QuestionId
        order by c.CreationDate desc
        limit 1
    ) as LatestCommentText,
    case when fr.ClosedDate is not null then coalesce(fr.CloseReason, 'Closed for unknown reason') else 'Open' end as QuestionStatus
from FinalResult fr
where fr.QuestionScore > 10
  and fr.TotalAnswers > 0
order by fr.Reputation desc, fr.QuestionScore desc
limit 100;