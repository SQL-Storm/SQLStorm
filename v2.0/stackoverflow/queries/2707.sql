-- {"query": "2707.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2157}
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        coalesce(sum(p.Score),0) as TotalPostScore,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 100
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
BadgeSummary as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBadges
    from Badges b
    group by b.UserId
),
TopVotedAnswers as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        a.CreationDate
    from Posts a
    where a.PostTypeId = 2 and a.Score > 0
),
AnswersWithAccepted as (
    select
        t.AnswerId,
        t.QuestionId,
        t.OwnerUserId,
        t.Score,
        t.AnswerRank,
        q.AcceptedAnswerId,
        q.Title,
        q.Tags,
        q.ClosedDate
    from TopVotedAnswers t
    join Posts q on q.Id = t.QuestionId and q.PostTypeId = 1
),
UserLinkStats as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        p1.OwnerUserId as OwnerUserIdPost,
        p2.OwnerUserId as OwnerUserIdRelated
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.CreationDate > (cast('2024-10-01' as date) - interval '180 days')
),
UserRecentComments as (
    select 
        c.UserId,
        count(*) as CommentsCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.CreationDate > (cast('2024-10-01' as date) - interval '90 days')
    group by c.UserId
),
UserVoteSummary as (
    select 
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesCast,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesCast,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoritesCast
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
),
ComplexUserMetrics as (
    select 
        rau.UserId,
        rau.DisplayName,
        rau.Reputation,
        rau.CreationDate,
        rau.LastAccessDate,
        rau.QuestionsPosted,
        rau.AnswersPosted,
        rau.TotalPostScore,
        coalesce(bs.GoldBadges,0) as GoldBadges,
        coalesce(bs.SilverBadges,0) as SilverBadges,
        coalesce(bs.BronzeBadges,0) as BronzeBadges,
        coalesce(case when bs.HasTagBadges then 1 else 0 end,0) as HasTagBadges,
        coalesce(uc.CommentsCount,0) as RecentCommentsCount,
        coalesce(uvs.UpVotesCast,0) as UpVotesCast,
        coalesce(uvs.DownVotesCast,0) as DownVotesCast
    from RecursiveUserActivity rau
    left join BadgeSummary bs on bs.UserId = rau.UserId
    left join UserRecentComments uc on uc.UserId = rau.UserId
    left join UserVoteSummary uvs on uvs.UserId = rau.UserId
),
TrendingQuestionsWithStats as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate,
        coalesce(closed.ReasonName, 'Open') as CloseReason,
        row_number() over (order by p.ViewCount desc, p.Score desc) as RankByViews,
        (
            select count(*) 
            from Posts ans 
            where ans.ParentId = p.Id and ans.Score > 5
        ) as HighScoringAnswerCount,
        (
            select string_agg(distinct lt.Name, ', ') 
            from PostLinks pl2 join LinkTypes lt on lt.Id = pl2.LinkTypeId 
            where pl2.PostId = p.Id
        ) as LinkedPostTypes,
        case when p.ClosedDate is null then 'Active' else 'Closed' end as PostStatus,
        substring(p.Tags, 2, length(p.Tags)-2) as ParsedTags
    from Posts p
    left join (
        select ph.PostId, crt.Name as ReasonName
        from PostHistory ph
        join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
        where ph.PostHistoryTypeId = 10
    ) closed on closed.PostId = p.Id
    where p.PostTypeId = 1 and p.CreationDate > (cast('2024-10-01' as date) - interval '180 days')
),
RecursiveTagUsage as (
    select 
        t.TagName,
        count(p.Id) as UsageCount,
        max(p.CreationDate) as LastUsedDate
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like '%' || t.TagName || '%'
    group by t.TagName
    having count(p.Id) > 100
),
WindowRankedAnswers as (
    select 
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        p.CreationDate,
        rank() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
FilteredPosts as (
    select distinct p.*
    from Posts p
    left join Votes v on v.PostId = p.Id and v.VoteTypeId = 2
    where p.Score > 3
      and (v.Id is null or v.CreationDate > (cast('2024-10-01' as date) - interval '365 days'))
      and p.CreationDate > (cast('2024-10-01' as date) - interval '730 days')
),
FinalSelection as (
    select 
        cume.UserId,
        cume.DisplayName,
        cume.Reputation,
        cume.QuestionsPosted,
        cume.AnswersPosted,
        cume.TotalPostScore,
        cume.GoldBadges,
        cume.SilverBadges,
        cume.BronzeBadges,
        cume.HasTagBadges,
        cume.RecentCommentsCount,
        cume.UpVotesCast,
        cume.DownVotesCast,
        coalesce(tf.RankByViews, 0) as QuestionRankByViews,
        coalesce(tf.CloseReason, 'N/A') as QuestionCloseReason,
        tf.ViewCount as QuestionViewCount,
        tf.FavoriteCount as QuestionFavoriteCount,
        tf.HighScoringAnswerCount,
        tf.PostStatus,
        tf.ParsedTags,
        ua.AnswerId,
        ua.Score as AnswerScore,
        ua.AnswerRank
    from ComplexUserMetrics cume
    left join AnswersWithAccepted ua on ua.OwnerUserId = cume.UserId
    left join TrendingQuestionsWithStats tf on tf.QuestionId = ua.QuestionId
    where cume.Reputation > 500 and (ua.AnswerRank = 1 or ua.AnswerRank is null)
    order by cume.Reputation desc, tf.ViewCount desc
    limit 100
)
select 
    fs.UserId,
    fs.DisplayName,
    fs.Reputation,
    fs.QuestionsPosted,
    fs.AnswersPosted,
    fs.TotalPostScore,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.HasTagBadges,
    fs.RecentCommentsCount,
    fs.UpVotesCast,
    fs.DownVotesCast,
    fs.QuestionRankByViews,
    coalesce(fs.QuestionCloseReason, 'Open') as QuestionCloseReason,
    fs.QuestionViewCount,
    fs.QuestionFavoriteCount,
    fs.HighScoringAnswerCount,
    fs.PostStatus,
    fs.ParsedTags,
    fs.AnswerId,
    fs.AnswerScore,
    fs.AnswerRank,
    length(fs.ParsedTags) as TagsLength,
    case 
        when fs.AnswerScore > 10 then 'Highly voted answer'
        when fs.AnswerScore between 5 and 10 then 'Moderately voted answer'
        else 'Low voted answer or no answer'
    end as AnswerVoteCategory,
    upper(split_part(fs.ParsedTags, '><', 1)) as LeadingTagUpper,
    (coalesce(fs.QuestionCloseReason, '') like '%Duplicate%') or false as IsDuplicateQuestion
from FinalSelection fs
where (case 
        when fs.AnswerScore > 10 then 'Highly voted answer'
        when fs.AnswerScore between 5 and 10 then 'Moderately voted answer'
        else 'Low voted answer or no answer'
      end != 'Low voted answer or no answer' or fs.QuestionsPosted > 5)
  and fs.PostStatus = 'Active'
order by fs.Reputation desc, fs.QuestionViewCount desc, fs.AnswerScore desc
limit 50;