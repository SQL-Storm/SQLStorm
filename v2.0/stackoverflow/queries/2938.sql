with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        coalesce(p.Tags, '') as Tags,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2)
),
TaggedQuestions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        -- convert tags like '<tag1><tag2>' into rows
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1
),
TopTagUsers as (
    select
        t.Tag,
        r.UserId,
        count(*) as PostsWithTag
    from TaggedQuestions t
    join RecursiveUserPosts r on r.PostId = t.QuestionId
    where r.RecentPostRank <= 10
    group by t.Tag, r.UserId
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.Date >= timestamp '2023-01-01'
    group by b.UserId, b.Class
),
UserAggregateStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when rp.PostTypeId=1 then 1 else 0 end),0) as QuestionCount,
        coalesce(sum(case when rp.PostTypeId=2 then 1 else 0 end),0) as AnswerCount,
        coalesce(sum(rp.Score),0) as TotalScore,
        coalesce(sum(rp.ViewCount),0) as TotalViews,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location
    from Users u
    left join RecursiveUserPosts rp on rp.UserId = u.Id
    left join (
        select
            UserId,
            max(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
            max(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
            max(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
        from UserBadgeCounts
        group by UserId
    ) ub on ub.UserId = u.Id
    group by u.Id, u.DisplayName, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
UserCloseVotes as (
    select
        ph.UserId,
        count(distinct ph.PostId) as CloseVotesCast,
        count(distinct case when ph.PostHistoryTypeId = 10 then ph.PostId end) as PostsClosedByUser
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.UserId
),
PostLinkedQuestions as (
    select
        pl.PostId,
        pl.RelatedPostId,
        l.Name as LinkTypeName,
        p1.PostTypeId as PostType1,
        p2.PostTypeId as PostType2,
        p1.Score as Post1Score,
        p2.Score as Post2Score,
        p1.CreationDate as Post1Created,
        p2.CreationDate as Post2Created
    from PostLinks pl
    join LinkTypes l on l.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where p1.PostTypeId = 1 and p2.PostTypeId = 1
),
RankedLinkedPosts as (
    select
        plq.PostId,
        plq.RelatedPostId,
        plq.LinkTypeName,
        plq.Post1Score,
        plq.Post2Score,
        row_number() over (partition by plq.PostId order by plq.Post2Score desc) as RelatedRank
    from PostLinkedQuestions plq
),
UserTopAnswersWithComments as (
    select
        a.OwnerUserId as UserId,
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        c.CommentCount,
        coalesce(c.TotalCommentLength,0) as TotalCommentLength,
        row_number() over (partition by a.OwnerUserId order by a.Score desc, a.CreationDate desc) as AnswerRank
    from Posts a
    left join (
        select
            PostId,
            count(*) as CommentCount,
            sum(char_length(Text)) as TotalCommentLength
        from Comments
        group by PostId
    ) c on c.PostId = a.Id
    where a.PostTypeId = 2 and a.OwnerUserId is not null
),
QuestionsWithAcceptedStatus as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AcceptedAnswerId,
        a.OwnerUserId as AcceptedAnswererId,
        a.Score as AcceptedAnswerScore
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
)
select
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalScore,
    uas.TotalViews,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    coalesce(ucv.CloseVotesCast,0) as CloseVotesCast,
    coalesce(ucv.PostsClosedByUser,0) as PostsClosedByUser,
    count(distinct tt.Tag) as DistinctTagsInTopPosts,
    avg(case when utac.AnswerRank <= 5 then utac.AnswerScore else null end) as AvgTop5AnswerScore,
    string_agg(distinct coalesce(tt.Tag, 'N/A'), ', ') as TopTags,
    max(rlp.RelatedRank) as MaxRelatedRank,
    max(qw.AcceptedAnswerScore) filter (where qw.AcceptedAnswererId = uas.UserId) as MaxAcceptedAnswerScore,
    (select count(*) from Votes v where v.UserId = uas.UserId and v.VoteTypeId = 2) as UpVotesCast,
    (select count(*) from Votes v where v.UserId = uas.UserId and v.VoteTypeId = 3) as DownVotesCast
from UserAggregateStats uas
left join UserCloseVotes ucv on ucv.UserId = uas.UserId
left join TopTagUsers tt on tt.UserId = uas.UserId
left join UserTopAnswersWithComments utac on utac.UserId = uas.UserId
left join RankedLinkedPosts rlp on rlp.RelatedPostId = (
    select max(PostId) from RecursiveUserPosts where UserId = uas.UserId and RecentPostRank = 1
)
left join QuestionsWithAcceptedStatus qw on qw.AcceptedAnswererId = uas.UserId
where uas.Reputation > 1000 and uas.QuestionCount > 10
group by
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalScore,
    uas.TotalViews,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    ucv.CloseVotesCast,
    ucv.PostsClosedByUser
having count(distinct tt.Tag) > 3
order by uas.Reputation desc, AvgTop5AnswerScore desc
limit 50;