with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as QuestionAnswerCount,
        coalesce(p.FavoriteCount, 0) as QuestionFavoriteCount,
        coalesce(u.Reputation, 0) as OwnerReputation,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn_latest_post
    from
        Tags t
    left join
        Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    left join
        Users u on u.Id = p.OwnerUserId
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from
        Badges b
    group by b.UserId
),
UserPostStats as (
    select
        p.OwnerUserId as UserId,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        avg(case when p.PostTypeId in (1,2) then p.Score end) as AvgPostScore,
        max(case when p.PostTypeId in (1,2) then p.Score end) as MaxPostScore,
        sum(case when p.PostTypeId = 1 then p.ViewCount else 0 end) as TotalQuestionViews,
        sum(case when p.PostTypeId = 1 then coalesce(p.FavoriteCount,0) else 0 end) as TotalQuestionFavorites
    from
        Posts p
    where
        p.OwnerUserId is not null
    group by
        p.OwnerUserId
),
QuestionAnswerDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswererId,
        a.OwnerDisplayName as AnswererDisplayName,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(*) over (partition by q.Id) as TotalAnswers
    from
        Posts q
    left join
        Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where
        q.PostTypeId = 1
),
TopAnswerers as (
    select
        AnswererId,
        count(*) as AnswersProvided,
        avg(AnswerScore) as AvgAnswerScore,
        sum(IsAccepted) as AcceptedAnswersCount
    from
        QuestionAnswerDetails
    where
        AnswererId is not null
    group by
        AnswererId
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.CreationDate,
        u.LastAccessDate,
        u.Reputation,
        us.QuestionsCount,
        us.AnswersCount,
        us.AvgPostScore,
        us.MaxPostScore,
        us.TotalQuestionViews,
        us.TotalQuestionFavorites,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        ta.AnswersProvided,
        ta.AvgAnswerScore,
        ta.AcceptedAnswersCount,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from
        Users u
    left join
        UserPostStats us on us.UserId = u.Id
    left join
        UserBadgeStats ub on ub.UserId = u.Id
    left join
        TopAnswerers ta on ta.AnswererId = u.Id
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalQuestionTitle,
        p2.Title as DuplicateQuestionTitle,
        pl.CreationDate as LinkCreationDate
    from
        PostLinks pl
    join
        Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join
        Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where
        pl.LinkTypeId = 3
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        p.Title,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserDisplayName
    from
        PostHistory ph
    join
        CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    join
        Posts p on p.Id = ph.PostId and p.PostTypeId = 1
    left join
        Users u on u.Id = ph.UserId
    where
        ph.PostHistoryTypeId = 10
),
TopCommentsOnPopularPosts as (
    select
        c.PostId,
        p.Title,
        c.Id as CommentId,
        c.Text,
        c.Score as CommentScore,
        c.CreationDate as CommentDate,
        u.DisplayName as CommenterDisplayName,
        row_number() over (partition by c.PostId order by c.Score desc, c.CreationDate asc) as rn
    from
        Comments c
    join
        Posts p on p.Id = c.PostId and p.ViewCount > 10000
    left join
        Users u on u.Id = c.UserId
),
StringManipulations as (
    select
        p.Id as PostId,
        p.Title,
        length(p.Body) as BodyLength,
        substring(p.Body from 1 for 100) as BodyPreview,
        position('<code>' in p.Body) as FirstCodeTagPos,
        case
            when p.Tags is not null then
                array_to_string(
                    (
                        select array_agg(distinct ttag) from (
                            select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as ttag
                        ) s
                    )
                    , ', '
                )
            else ''
        end as NormalizedTags
    from
        Posts p
    where
        p.PostTypeId = 1
    group by p.Id, p.Title, p.Body, p.Tags
),
UnionExample as (
    select 'Gold' as BadgeClass, count(*) as Count from Badges where Class = 1
    union all
    select 'Silver' as BadgeClass, count(*) as Count from Badges where Class = 2
    union all
    select 'Bronze' as BadgeClass, count(*) as Count from Badges where Class = 3
)
select
    uaw.Id as UserId,
    uaw.DisplayName,
    uaw.Reputation,
    uaw.QuestionsCount,
    uaw.AnswersCount,
    uaw.GoldBadges,
    uaw.SilverBadges,
    uaw.BronzeBadges,
    uaw.AnswersProvided,
    uaw.AcceptedAnswersCount,
    dt.OriginalQuestionTitle,
    dt.DuplicateQuestionTitle,
    dt.LinkCreationDate,
    cq.Title as ClosedQuestionTitle,
    cq.CloseDate,
    cq.CloseReason,
    cq.ClosedByUserDisplayName,
    tc.PostId as PopularPostId,
    tc.Title as PopularPostTitle,
    tc.CommentId,
    tc.Text as CommentText,
    tc.CommentScore,
    sm.BodyLength,
    sm.BodyPreview,
    sm.FirstCodeTagPos,
    sm.NormalizedTags,
    ub.BadgeClass,
    ub.Count as BadgeCount
from
    UserActivityWindow uaw
left join
    DuplicateLinks dt on dt.PostId = (
        select Id from Posts where OwnerUserId = uaw.Id and PostTypeId = 1 order by CreationDate desc limit 1
    )
left join
    ClosedQuestionsWithReasons cq on cq.ClosedByUserId = uaw.Id
left join
    TopCommentsOnPopularPosts tc on tc.CommenterDisplayName = uaw.DisplayName
left join
    StringManipulations sm on sm.PostId = (
        select Id from Posts where OwnerUserId = uaw.Id and PostTypeId = 1 order by ViewCount desc limit 1
    )
left join
    UnionExample ub on ub.BadgeClass = (
        case
            when coalesce(uaw.GoldBadges,0) > 0 then 'Gold'
            when coalesce(uaw.SilverBadges,0) > 0 then 'Silver'
            when coalesce(uaw.BronzeBadges,0) > 0 then 'Bronze'
            else null
        end
    )
where
    uaw.UserRank <= 100
order by
    uaw.Reputation desc,
    uaw.AnswersCount desc,
    uaw.GoldBadges desc
limit 50;