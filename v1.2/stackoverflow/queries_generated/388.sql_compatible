with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    left join Comments c on c.UserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod and DownMod
        group by PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
), LatestPostEdits as (
    select ph.PostId, max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
    group by ph.PostId
), PostScoreStats as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        p.ContentLicense,
        lpe.LastEditDate,
        rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRankPerUser,
        avg(p.Score) over (partition by p.OwnerUserId) as AvgScorePerUser,
        count(*) over (partition by p.OwnerUserId) as PostsPerUser
    from Posts p
    left join LatestPostEdits lpe on lpe.PostId = p.Id
), DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate, pl.LinkTypeId
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicate
), UserBadgeSummary as (
    select 
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
), UserPostVotes as (
    select 
        p.OwnerUserId as UserId,
        v.VoteTypeId,
        count(*) as VoteCount
    from Votes v
    join Posts p on p.Id = v.PostId
    group by p.OwnerUserId, v.VoteTypeId
), UserActivityWithBadges as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.TotalVotesReceived,
        ua.UserRank,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.TotalBadges,0) as TotalBadges,
        coalesce(ubs.LastBadgeDate, timestamp '1970-01-01') as LastBadgeDate,
        coalesce(upv_up.VoteCount,0) as UpVotesReceived,
        coalesce(upv_down.VoteCount,0) as DownVotesReceived
    from RecursiveUserActivity ua
    left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
    left join UserPostVotes upv_up on upv_up.UserId = ua.UserId and upv_up.VoteTypeId = 2
    left join UserPostVotes upv_down on upv_down.UserId = ua.UserId and upv_down.VoteTypeId = 3
), TopQuestionsWithDuplicates as (
    select 
        ps.Id as QuestionId,
        ps.Title,
        ps.Tags,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.ClosedDate,
        ps.OwnerUserId,
        ua.DisplayName as OwnerDisplayName,
        ua.Reputation as OwnerReputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.TotalBadges,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        dl.RelatedPostId as DuplicateOfPostId,
        p2.Title as DuplicateOfTitle,
        p2.Score as DuplicateOfScore,
        case 
            when ps.ClosedDate is not null then 'Closed'
            else 'Open'
        end as PostStatus,
        row_number() over (order by ps.Score desc, ps.ViewCount desc) as RankByScore,
        ps.AcceptedAnswerId
    from PostScoreStats ps
    join UserActivityWithBadges ua on ua.UserId = ps.OwnerUserId
    left join DuplicateLinks dl on dl.PostId = ps.Id
    left join Posts p2 on p2.Id = dl.RelatedPostId
    where ps.PostTypeId = 1 -- Questions only
), QuestionsWithAcceptedAnswerStats as (
    select 
        tq.QuestionId,
        tq.Title,
        tq.Tags,
        tq.Score,
        tq.ViewCount,
        tq.AnswerCount,
        tq.CommentCount,
        tq.FavoriteCount,
        tq.ClosedDate,
        tq.OwnerUserId,
        tq.OwnerDisplayName,
        tq.OwnerReputation,
        tq.GoldBadges,
        tq.SilverBadges,
        tq.BronzeBadges,
        tq.TotalBadges,
        tq.UpVotesReceived,
        tq.DownVotesReceived,
        tq.DuplicateOfPostId,
        tq.DuplicateOfTitle,
        tq.DuplicateOfScore,
        tq.PostStatus,
        tq.RankByScore,
        tq.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwnerUserId,
        u2.DisplayName as AcceptedAnswerOwnerDisplayName,
        u2.Reputation as AcceptedAnswerOwnerReputation,
        u2.GoldBadges as AcceptedAnswerOwnerGoldBadges,
        u2.SilverBadges as AcceptedAnswerOwnerSilverBadges,
        u2.BronzeBadges as AcceptedAnswerOwnerBronzeBadges
    from TopQuestionsWithDuplicates tq
    left join Posts a on a.Id = tq.AcceptedAnswerId
    left join UserActivityWithBadges u2 on u2.UserId = a.OwnerUserId
), FinalRankedQuestions as (
    select 
        q.*,
        dense_rank() over (partition by q.PostStatus order by q.Score desc) as RankWithinStatus
    from QuestionsWithAcceptedAnswerStats q
)
select 
    frq.RankByScore,
    frq.RankWithinStatus,
    frq.QuestionId,
    frq.Title,
    frq.Tags,
    frq.Score,
    frq.ViewCount,
    frq.AnswerCount,
    frq.CommentCount,
    frq.FavoriteCount,
    frq.PostStatus,
    frq.OwnerUserId,
    frq.OwnerDisplayName,
    frq.OwnerReputation,
    frq.GoldBadges,
    frq.SilverBadges,
    frq.BronzeBadges,
    frq.TotalBadges,
    frq.UpVotesReceived,
    frq.DownVotesReceived,
    frq.DuplicateOfPostId,
    frq.DuplicateOfTitle,
    frq.DuplicateOfScore,
    frq.AcceptedAnswerScore,
    frq.AcceptedAnswerOwnerUserId,
    frq.AcceptedAnswerOwnerDisplayName,
    frq.AcceptedAnswerOwnerReputation,
    frq.AcceptedAnswerOwnerGoldBadges,
    frq.AcceptedAnswerOwnerSilverBadges,
    frq.AcceptedAnswerOwnerBronzeBadges,
    coalesce(split_part(trim(both '<>' from frq.Tags), '><', 1), 'NoTag') as FirstTag,
    case 
        when frq.Score > 10 and frq.ViewCount < 100 then 'HighScoreLowView'
        else 'Normal'
    end as ScoreViewFlag,
    avg(frq.Score) over (partition by frq.OwnerUserId) as AvgOwnerQuestionScore,
    (select count(*) from Comments c where c.PostId = frq.AcceptedAnswerOwnerUserId) as CommentsOnAcceptedAnswer,
    coalesce(frq.AcceptedAnswerScore, 0) as AcceptedAnswerScoreNonNull
from FinalRankedQuestions frq
where frq.RankByScore <= 100
order by frq.RankByScore;