with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) as HighestBadgeClass,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    where u.Location is not null
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
TopTags as (
    select
        t.TagName,
        t.Count,
        p.OwnerUserId,
        count(p.Id) as PostsWithTag
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like '%' || '<' || t.TagName || '>' || '%'
    group by t.TagName, t.Count, p.OwnerUserId
    having count(p.Id) > 10
),
UserTopTags as (
    select
        tua.UserId,
        tua.DisplayName,
        tt.TagName,
        tt.PostsWithTag,
        row_number() over (partition by tua.UserId order by tt.PostsWithTag desc) as TagRank
    from RecursiveUserActivity tua
    join TopTags tt on tt.OwnerUserId = tua.UserId
),
PostScoresWithVotes as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotes,
        coalesce(sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end),0) as TotalBounty,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.CreationDate, p.Title, p.Tags, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount
),
UserPostAggregates as (
    select
        p.OwnerUserId as UserId,
        count(p.PostId) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as TotalQuestions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as TotalAnswers,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        sum(p.UpVotes) as TotalUpVotes,
        sum(p.DownVotes) as TotalDownVotes,
        sum(p.TotalBounty) as TotalBountyEarned,
        sum(p.ViewCount) as TotalViews,
        sum(p.FavoriteCount) as TotalFavorites
    from PostScoresWithVotes p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        p.Title,
        p.OwnerUserId
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId = 10
),
UserCloseStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct cq.PostId) as ClosedQuestionsCount,
        count(distinct case when cq.CloseReason = 'Duplicate' then cq.PostId end) as DuplicateClosedCount,
        count(distinct case when cq.CloseReason = 'Off-topic' then cq.PostId end) as OffTopicClosedCount,
        count(distinct case when cq.CloseReason = 'Needs details or clarity' then cq.PostId end) as NeedsDetailsClosedCount
    from Users u
    left join ClosedQuestionsWithReasons cq on cq.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
UserActivitySummary as (
    select
        tua.UserId,
        tua.DisplayName,
        tua.Location,
        tua.Reputation,
        upa.TotalPosts,
        upa.TotalQuestions,
        upa.TotalAnswers,
        upa.AvgPostScore,
        upa.MaxPostScore,
        upa.TotalUpVotes,
        upa.TotalDownVotes,
        upa.TotalBountyEarned,
        upa.TotalViews,
        upa.TotalFavorites,
        ucs.ClosedQuestionsCount,
        ucs.DuplicateClosedCount,
        ucs.OffTopicClosedCount,
        ucs.NeedsDetailsClosedCount,
        (select string_agg(distinct ut.TagName, ', ') from UserTopTags ut where ut.UserId = tua.UserId and ut.TagRank <= 3) as TopTags
    from RecursiveUserActivity tua
    left join UserPostAggregates upa on upa.UserId = tua.UserId
    left join UserCloseStats ucs on ucs.UserId = tua.UserId
)
select
    uas.UserId,
    uas.DisplayName,
    coalesce(aes.AvgEditCount,0) as AvgEditsPerPost,
    uas.Location,
    uas.Reputation,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.AvgPostScore,
    uas.MaxPostScore,
    uas.TotalUpVotes,
    uas.TotalDownVotes,
    uas.TotalBountyEarned,
    uas.TotalViews,
    uas.TotalFavorites,
    uas.ClosedQuestionsCount,
    uas.DuplicateClosedCount,
    uas.OffTopicClosedCount,
    uas.NeedsDetailsClosedCount,
    uas.TopTags,
    case
        when uas.Reputation > 100000 then 'Legendary'
        when uas.Reputation > 10000 then 'Expert'
        when uas.Reputation > 1000 then 'Intermediate'
        else 'Beginner'
    end as UserLevel,
    dense_rank() over (order by uas.Reputation desc) as ReputationRank
from UserActivitySummary uas
left join (
    select
        ph.UserId,
        avg(edits.EditCount) as AvgEditCount
    from PostHistory ph
    join (
        select PostId, count(*) as EditCount
        from PostHistory
        where PostHistoryTypeId in (4,5,6,7,8,9,14)
        group by PostId
    ) edits on edits.PostId = ph.PostId
    where ph.UserId is not null
    group by ph.UserId
) aes on aes.UserId = uas.UserId
where coalesce(uas.TotalPosts,0) > 50
order by uas.Reputation desc, uas.TotalPosts desc
limit 100;