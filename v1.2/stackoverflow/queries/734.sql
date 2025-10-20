with RecursiveBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
TopBadges as (
    select UserId, DisplayName, BadgeName, Class, Date
    from RecursiveBadges
    where rn <= 3
),
PostScores as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.CommentCount,0) as CommentCount,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as PostRank
    from Posts p
    where p.PostTypeId in (1,2)
),
UserPostSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(p.Score) as TotalScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        avg(p.Score) as AvgScore,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        sum(p.AnswerCount) as TotalAnswersToQuestions,
        sum(p.FavoriteCount) as TotalFavorites,
        max(p.ViewCount) as MaxViews,
        (
          select string_agg(tag_txt, ', ')
          from (
            select distinct substring(t.TagName from 1 for 15) as tag_txt, t.Count as cnt
            from Posts p2
            left join lateral (
              select unnest(string_to_array(substring(p2.Tags from 2 for length(p2.Tags)-2), '><')) as TagName
            ) tags_unnest2 on true
            left join Tags t on tags_unnest2.TagName = t.TagName
            where p2.OwnerUserId = u.Id
            order by cnt desc, tag_txt
          ) s
        ) as TopTags
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    group by u.Id, u.DisplayName
),
PostWithAnswerDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.CreationDate as AnswerDate,
        a.Score as AnswerScore,
        a.CommentCount as AnswerComments,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TopAnswers as (
    select *
    from PostWithAnswerDetails
    where AnswerRank <= 2
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes crt on (case when ph.Comment ~ '^[0-9]+$' then cast(ph.Comment as integer) end) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserVoteAnalysis as (
    select
        v.UserId,
        vt.Name as VoteType,
        count(*) as VoteCount,
        sum(coalesce(v.BountyAmount, 0)) as TotalBounty
    from Votes v
    inner join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.UserId, vt.Name
),
UserLastActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(p.LastActivityDate) as LastPostActivity,
        max(c.CreationDate) as LastCommentDate,
        greatest(
            max(p.LastActivityDate),
            max(c.CreationDate),
            u.LastAccessDate
        ) as LastOverallActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.LastAccessDate
),
UserAggregated as (
    select
        ups.UserId,
        ups.DisplayName,
        ups.TotalPosts,
        ups.TotalScore,
        ups.MaxScore,
        ups.MinScore,
        ups.AvgScore,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.TotalAnswersToQuestions,
        ups.TotalFavorites,
        ups.MaxViews,
        ups.TopTags,
        uva.VoteType,
        uva.VoteCount,
        uva.TotalBounty,
        ula.LastOverallActivity
    from UserPostSummary ups
    left join UserVoteAnalysis uva on ups.UserId = uva.UserId
    left join UserLastActivity ula on ups.UserId = ula.UserId
),
CombinedResults as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.TotalPosts,
        ua.TotalScore,
        ua.MaxScore,
        ua.MinScore,
        ua.AvgScore,
        coalesce(sum(case when ua.VoteType = 'UpMod' then ua.VoteCount else 0 end),0) as UpVotes,
        coalesce(sum(case when ua.VoteType = 'DownMod' then ua.VoteCount else 0 end),0) as DownVotes,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalAnswersToQuestions,
        ua.TotalFavorites,
        ua.MaxViews,
        ua.TopTags,
        ua.LastOverallActivity,
        tb.BadgeName,
        tb.Class as BadgeClass,
        crc.CloseReason,
        crc.CloseCount
    from UserAggregated ua
    left join TopBadges tb on ua.UserId = tb.UserId
    left join CloseReasonCounts crc on crc.PostId in (
        select p.Id from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId = 1
    )
    group by
        ua.UserId, ua.DisplayName, ua.TotalPosts, ua.TotalScore, ua.MaxScore, ua.MinScore, ua.AvgScore,
        ua.QuestionCount, ua.AnswerCount, ua.TotalAnswersToQuestions, ua.TotalFavorites, ua.MaxViews, ua.TopTags,
        ua.LastOverallActivity, tb.BadgeName, tb.Class, crc.CloseReason, crc.CloseCount
)
select
    UserId,
    DisplayName,
    TotalPosts,
    TotalScore,
    MaxScore,
    MinScore,
    cast(round(AvgScore, 2) as numeric(18,2)) as AvgScore,
    UpVotes,
    DownVotes,
    QuestionCount,
    AnswerCount,
    TotalAnswersToQuestions,
    TotalFavorites,
    MaxViews,
    TopTags,
    LastOverallActivity,
    BadgeName,
    BadgeClass,
    CloseReason,
    CloseCount,
    case
        when TotalScore > 1000 then 'High Scorer'
        when TotalScore between 500 and 1000 then 'Medium Scorer'
        else 'Low Scorer'
    end as ScoreCategory,
    case
        when LastOverallActivity > (cast('2024-10-01 12:34:56' as timestamp) - interval '30 day') then 'Active'
        else 'Inactive'
    end as ActivityStatus
from CombinedResults
where TotalPosts > 10
order by TotalScore desc, TotalPosts desc
limit 100;